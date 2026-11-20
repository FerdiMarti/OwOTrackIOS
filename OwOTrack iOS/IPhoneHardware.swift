//
//  DeviceHardware.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 19.12.22.
//
#if os(iOS)

import Foundation
import AVFoundation
import CoreHaptics
import AudioToolbox
import UIKit
import CoreLocation

//static functions for iPhone hardware stuff
class IPhoneHardware: DeviceHardware {
    static let audioSession = AVAudioSession.sharedInstance()
    static let locationManager = CLLocationManager()
    //iOS 17+: keeps the app "in use" while in the background. AnyObject because the class only exists since iOS 17
    static var backgroundActivitySession: AnyObject?
    
    static func unregisterVolButtonListener(target: NSObject) {
        if audioSession.observationInfo != nil {
            audioSession.removeObserver(target, forKeyPath: "outputVolume")
        }
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("audioSession could not be deinitialized")
        }
    }

    //the audio session is only active so that volume button presses show up as outputVolume changes.
    //ambient mixes with other apps' audio, so music keeps playing (the default category would stop it)
    static func registerVolButtonListener(target: NSObject) {
        do {
            try audioSession.setCategory(.ambient)
            try audioSession.setActive(true)
        } catch {
            print("audioSession could not be initialized")
        }
        //old and new value tell volume up from volume down
        audioSession.addObserver(target, forKeyPath: "outputVolume", options: [.old, .new], context: nil)
    }
    
    //one haptic engine for the whole app, created on first use (nil if the device has no haptics).
    //creating a new engine for every vibration leaked each of them: its reset handler kept it alive
    static let hapticEngine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else {
            return nil
        }
        // If something goes wrong, attempt to restart the engine immediately
        engine.resetHandler = { [weak engine] in
            print("The haptic engine reset")
            try? engine?.start()
        }
        return engine
    }()

    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        guard let engine = hapticEngine else { return false }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: a)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: f)
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: TimeInterval(d))

        do {
            try engine.start()  //start before each use: the system stops the engine, e.g. while the app is in the background
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
            return false
        }
    }
    
    static func vibrate() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    //when enabled, the screen turns off if the sensor on the earpiece is covered
    static func startProximitySensor() {
        DispatchQueue.main.async {
            UIDevice.current.isProximityMonitoringEnabled = true
        }
    }
    
    static func stopProximitySensor() {
        DispatchQueue.main.async {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }

    //a locked phone puts the app in the background, so keep it from locking automatically while tracking.
    //covering the proximity sensor still turns the screen off, and the app stays in the foreground then
    static func preventAutoLock() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    static func allowAutoLock() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    static func getBatteryLevel() -> Float? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : level  //iOS reports -1 while the level is unknown
    }
    
    static func startBatteryLevelMonitoring() {
        //additionally non async to enable it immediately
        UIDevice.current.isBatteryMonitoringEnabled = true
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }
    
    static func stopBatteryLevelMonitoring() {
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }
    
    //uses background location to keep the app running in background
    static func startBackgroundUsage(target: CLLocationManagerDelegate) {
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        //iOS pauses location updates while the phone doesn't move (e.g. strapped to the body in one room),
        //and a background app whose updates are paused gets suspended
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 99999
        locationManager.delegate = target
        locationManager.startUpdatingLocation()
        //only becomes active when started while the app is in the foreground, which it is when Connect is pressed
        if #available(iOS 17.0, *), backgroundActivitySession == nil {
            backgroundActivitySession = CLBackgroundActivitySession()
        }
    }

    static func stopBackgroundUsage() {
        locationManager.stopUpdatingLocation()
        if #available(iOS 17.0, *) {
            (backgroundActivitySession as? CLBackgroundActivitySession)?.invalidate()
        }
        backgroundActivitySession = nil
    }
    
    //generates a random MAC address for SlimeVR (if not already generated before) and saves it in UserDefaults, actual MAC address can not be accessed
    static func getPseudoMacAddress() -> [UInt8] {
        let defaults = UserDefaults.standard
        if let mac = defaults.object(forKey: "mac") as? [UInt8] {
            return mac
        } else {
            var mac : [UInt8] = []
            while (mac.count < 6) {
                let rand = Int.random(in: 0..<255)
                mac.append(UInt8(rand))
            }
            defaults.set(mac, forKey: "mac")
            return mac
        }
    }
}
#endif
