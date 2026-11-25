//
//  WatchHardware.swift
//  OwOTrack WatchOS
//
//  Created by Ferdinand Martini on 21.12.22.
//
#if os(watchOS)

import Foundation
import CoreLocation
import HealthKit
import WatchKit
import Combine

let MAC_USERDEFAULTS_KEY = "mac"
let SAVE_WORKOUTS_USERDEFAULTS_KEY = "saveWorkouts"

//static functions for Apple Watch hardware stuff
class WatchHardware: DeviceHardware {

    //Apple Watch has no volume buttons, so there is nothing to listen for
    static func unregisterVolButtonListener(target: NSObject) {
    }

    static func registerVolButtonListener(target: NSObject) {
    }

    //not sure if that is possible on Apple Watch, use normal vibrate
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool  {
        vibrate()
        return true
    }

    static func vibrate() {
        WKInterfaceDevice.current().play(.click)
    }

    //does not exist on Apple Watch
    static func startProximitySensor() {
        return
    }

    static func stopProximitySensor() {
        return
    }

    //the watch screen sleeps when the wrist is lowered; keeping the app running there needs a workout session instead
    static func preventAutoLock() {
    }

    static func allowAutoLock() {
    }

    static func getBatteryLevel() -> Float? {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? nil : level  //watchOS reports -1 while the level is unknown
    }

    static func startBatteryLevelMonitoring() {
        //additionally non async to enable it immediately
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        DispatchQueue.main.async {
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        }
    }

    static func stopBatteryLevelMonitoring() {
        DispatchQueue.main.async {
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        }
    }

    //watchOS keeps an app with an active workout running, also when the wrist is lowered or the screen is off:
    //tracking records a workout (WorkoutRecorder), saved to Health when it ends
    static func startBackgroundUsage(target: CLLocationManagerDelegate?) {
        DispatchQueue.main.async {
            WorkoutRecorder.shared.start()
        }
    }

    static func stopBackgroundUsage() {
        DispatchQueue.main.async {
            WorkoutRecorder.shared.stop()
        }
    }

    //generates a random MAC address for SlimeVR (if not already generated before) and saves it in UserDefaults, actual MAC address can not be accessed
    static func getPseudoMacAddress() -> [UInt8] {
        let defaults = UserDefaults.standard
        if let mac = defaults.object(forKey: MAC_USERDEFAULTS_KEY) as? [UInt8] {
            return mac
        } else {
            var mac : [UInt8] = []
            while (mac.count < 6) {
                let rand = Int.random(in: 0..<255)
                mac.append(UInt8(rand))
            }
            defaults.set(mac, forKey: MAC_USERDEFAULTS_KEY)
            return mac
        }
    }
}

//the workout while the watch tracks. It keeps the app running with the wrist down (watchOS keeps an app with an
//active workout running, and only then can the iPhone still message it), and is saved to Health as a Fitness Gaming
//workout when tracking ends, with its length only: nothing is read or measured for it. Not saved: sessions shorter than
//a minute (a connection that didn't work out), or when saving is switched off. All on the main thread
final class WorkoutRecorder: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    static let shared = WorkoutRecorder()
    static let minimumDuration: TimeInterval = 60
    static let endingTimeout: TimeInterval = 5      //how long the next workout waits for the previous one to end
    static let maxFailedStarts = 3

    @Published var shownSummary: WorkoutSummary?        //the session just saved, shown once
    @Published var savesWorkouts: Bool {
        didSet { UserDefaults.standard.set(savesWorkouts, forKey: SAVE_WORKOUTS_USERDEFAULTS_KEY) }
    }
    var onSaved: ((WorkoutSummary) -> Void)?             //tells the iPhone

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?          //without a data source: it only saves the workout
    private var startDate: Date?
    private var wanted = false          //false once tracking stopped, so a late permission answer doesn't start a workout
    //the previous workout, until watchOS has ended its session and saved or discarded it. The next one only starts
    //after that: a workout started while the previous one is still ending may not run, and then nothing keeps the app
    //running once the screen turns off
    private var endingSession: HKWorkoutSession?
    private var finishingSession: HKWorkoutSession?
    private var endingTimer: Timer?
    private var failedStarts = 0
    private var failureLogged = false

    private override init() {
        savesWorkouts = UserDefaults.standard.object(forKey: SAVE_WORKOUTS_USERDEFAULTS_KEY) as? Bool ?? true
        super.init()
        //a workout can't start while the app is in the background (wrist down right after Connect): try again
        //when the app is on screen again
        NotificationCenter.default.addObserver(forName: WKApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.wanted, self.session == nil else {
                return
            }
            self.failedStarts = 0
            self.startWorkout()
        }
    }

    func start() {
        wanted = true
        failedStarts = 0
        failureLogged = false
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        #if DEBUG
        if ConnectionModel.screenshotAction != nil {
            return      //App Store screenshots in the simulator: no Health prompt in the way
        }
        #endif
        //a workout session needs permission to save workouts. watchOS asks once, on the first connect
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: nil) { _, _ in
            DispatchQueue.main.async {
                self.startWorkout()
            }
        }
    }

    private func startWorkout() {
        if !wanted || session != nil {
            return
        }
        if endingSession != nil || finishingSession != nil {
            return      //once the previous workout is done (previousDone)
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .fitnessGaming
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            self.session = session
            self.builder = builder
            startDate = start
        } catch {
            logFailure("Couldn't start the workout, tracking will stop when the screen turns off: \(error.localizedDescription)")
        }
    }

    func stop() {
        wanted = false
        if let session = session {
            close(session)
        }
    }

    //ends the workout and saves it (or discards a short one). The next workout waits until both are done
    private func close(_ session: HKWorkoutSession) {
        guard session === self.session, let builder = builder, let start = startDate else {
            return
        }
        self.session = nil
        self.builder = nil
        startDate = nil
        endingSession = session
        finishingSession = session
        endingTimer?.invalidate()
        endingTimer = Timer.scheduledTimer(withTimeInterval: WorkoutRecorder.endingTimeout, repeats: false) { [weak self] _ in
            //watchOS didn't report the end in time: the next workout doesn't wait any longer
            self?.endingSession = nil
            self?.finishingSession = nil
            self?.previousDone()
        }
        let end = Date()
        switch session.state {
        case .notStarted, .ended:
            endingSession = nil     //it never started, or watchOS ended it: nothing left to end
        default:
            session.end()
        }
        let summary = WorkoutSummary(start: start, duration: end.timeIntervalSince(start))
        let save = savesWorkouts && summary.duration >= WorkoutRecorder.minimumDuration
        builder.endCollection(withEnd: end) { _, _ in
            guard save else {
                builder.discardWorkout()
                DispatchQueue.main.async {
                    self.finished(session)
                }
                return
            }
            builder.finishWorkout { workout, error in
                DispatchQueue.main.async {
                    self.finished(session)
                    if workout == nil {
                        Logger.getInstance().addEntry("Couldn't save the workout to Health: \(error?.localizedDescription ?? "unknown error")")
                        return
                    }
                    Logger.getInstance().addEntry("Saved to Health as a workout: \(summary.durationText)")
                    self.shownSummary = summary
                    self.onSaved?(summary)
                }
            }
        }
    }

    private func finished(_ session: HKWorkoutSession) {
        if finishingSession === session {
            finishingSession = nil
            previousDone()
        }
    }

    //the previous workout has ended and is saved or discarded: tracking that started meanwhile gets its workout now
    private func previousDone() {
        guard endingSession == nil, finishingSession == nil else {
            return
        }
        endingTimer?.invalidate()
        endingTimer = nil
        if wanted && failedStarts <= WorkoutRecorder.maxFailedStarts {
            startWorkout()
        }
    }

    //once per tracking session: a workout that can't start is tried again, quietly
    private func logFailure(_ message: String) {
        if !failureLogged {
            failureLogged = true
            Logger.getInstance().addEntry(message)
        }
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            if workoutSession === self.session {
                if toState == .running {
                    self.failedStarts = 0
                    Logger.getInstance().addEntry("Workout running: tracking continues with the screen off")
                } else if toState == .ended {
                    //not ended by the app: e.g. another app started a workout. Saved as far as it got, and not
                    //started again, which would end the other app's workout in turn
                    Logger.getInstance().addEntry("watchOS ended the workout, tracking may stop when the screen turns off")
                    self.wanted = false
                    self.close(workoutSession)
                }
            } else if workoutSession === self.endingSession, toState == .ended {
                self.endingSession = nil
                self.previousDone()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if workoutSession === self.endingSession {
                self.endingSession = nil
                self.previousDone()
            } else if workoutSession === self.session {
                //tried again once it's closed (previousDone), a few times, and whenever the app comes back on screen
                self.logFailure("Workout failed, tracking may stop when the screen turns off: \(error.localizedDescription)")
                self.failedStarts += 1
                self.close(workoutSession)
            }
        }
    }

    #if DEBUG
    //App Store screenshots: the summary of a session that was saved
    func runScreenshotAction() {
        if ConnectionModel.screenshotAction == "summary" {
            shownSummary = WorkoutSummary(start: Date().addingTimeInterval(-50 * 60), duration: 45 * 60 + 12)
        }
    }
    #endif
}
#endif
