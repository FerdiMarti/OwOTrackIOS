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

let MAC_USERDEFAULTS_KEY = "mac"

//static functions for Apple Watch hardware stuff
class WatchHardware: DeviceHardware {
    static let healthStore = HKHealthStore()
    static let workoutDelegate = WorkoutSessionDelegate()
    //only used on the main thread
    static var workoutSession: HKWorkoutSession?
    static var workoutWanted = false    //false once tracking stopped, so a late permission answer doesn't start a session

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

    //watchOS keeps an app with an active workout session running, also when the wrist is lowered or the screen is off.
    //the session only runs while tracking and is ended afterwards; nothing is saved to Health
    static func startBackgroundUsage(target: CLLocationManagerDelegate?) {
        DispatchQueue.main.async {
            workoutWanted = true
            guard HKHealthStore.isHealthDataAvailable() else {
                return
            }
            //starting a workout session needs permission to share workouts, watchOS only asks the first time
            healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: nil) { _, _ in
                DispatchQueue.main.async {
                    startWorkoutSession()
                }
            }
        }
    }

    private static func startWorkoutSession() {
        if !workoutWanted || workoutSession != nil {
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .fitnessGaming
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = workoutDelegate
            session.startActivity(with: Date())
            workoutSession = session
        } catch {
            Logger.getInstance().addEntry("Couldn't start the workout session, tracking will stop when the screen turns off: \(error.localizedDescription)")
        }
    }

    static func stopBackgroundUsage() {
        DispatchQueue.main.async {
            workoutWanted = false
            workoutSession?.end()
            workoutSession = nil
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

//reports a workout session that fails while tracking
final class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Logger.getInstance().addEntry("Workout session failed, tracking may stop when the screen turns off: \(error.localizedDescription)")
    }
}
#endif
