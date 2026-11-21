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
//active workout running), and is saved to Health as a Fitness Gaming workout when tracking ends, with its length only:
//nothing is read or measured for it. Not saved: sessions shorter than a minute (a connection that didn't work out),
//or when saving is switched off. All on the main thread
final class WorkoutRecorder: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    static let shared = WorkoutRecorder()
    static let minimumDuration: TimeInterval = 60

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

    private override init() {
        savesWorkouts = UserDefaults.standard.object(forKey: SAVE_WORKOUTS_USERDEFAULTS_KEY) as? Bool ?? true
        super.init()
    }

    func start() {
        wanted = true
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
            Logger.getInstance().addEntry("Couldn't start the workout, tracking will stop when the screen turns off: \(error.localizedDescription)")
        }
    }

    func stop() {
        wanted = false
        guard let session = session, let builder = builder, let start = startDate else {
            return
        }
        self.session = nil
        self.builder = nil
        startDate = nil
        let end = Date()
        session.end()
        let summary = WorkoutSummary(start: start, duration: end.timeIntervalSince(start))
        let save = savesWorkouts && summary.duration >= WorkoutRecorder.minimumDuration
        builder.endCollection(withEnd: end) { _, _ in
            guard save else {
                builder.discardWorkout()
                return
            }
            builder.finishWorkout { workout, error in
                DispatchQueue.main.async {
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

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            Logger.getInstance().addEntry("Workout failed, tracking may stop when the screen turns off: \(error.localizedDescription)")
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
