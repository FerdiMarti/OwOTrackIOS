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
    
    static func unregisterVolButtonListener(target: NSObject) {
        if audioSession.observationInfo != nil {
            audioSession.removeObserver(target, forKeyPath: "outputVolume")
        }
        do {
            try audioSession.setActive(false)
        } catch {
            print("audioSession could not be deinitialized")
        }
    }
    
    static func registerVolButtonListener(target: NSObject) {
        do {
            try audioSession.setActive(true)
        } catch {
            print("audioSession could not be initialized")
        }
        audioSession.addObserver(target, forKeyPath: "outputVolume", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    @available(iOS 13.0, *)
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        var engine: CHHapticEngine?
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
            return false
        }

        // If something goes wrong, attempt to restart the engine immediately
        engine?.resetHandler = { 
            print("The engine reset")

            do {
                try engine?.start()
            } catch {
                print("Failed to restart the engine: \(error)")
            }
        }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: a)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: f)
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: TimeInterval(d))

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 1)
            print("Vibration Done")
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
    
    static func getBatteryLevel() -> Float {
        return abs(UIDevice.current.batteryLevel)
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
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
                case .notDetermined, .restricted, .denied:
                    print("no loaction access")
                case .authorizedAlways, .authorizedWhenInUse:
                    print("location access")
                @unknown default:
                break
            }
        }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 99999
        locationManager.delegate = target
        locationManager.startUpdatingLocation()
    }
    
    static func stopBackgroundUsage() {
        locationManager.stopUpdatingLocation()
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
