//
//  DeviceHardware.swift
//  OwOTrack WatchKit Extension
//
//  Created by Ferdinand Martini on 21.12.22.
//
#if os(watchOS)

import Foundation
import AVFoundation
import UIKit
import CoreLocation
import WatchKit

let MAC_USERDEFAULTS_KEY = "mac"

//static functions for Apple Watch hardware stuff
class WatchHardware: DeviceHardware {
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
    
    //not sure if that is possible on Apple Watch, use normal vibrate
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool  {
        vibrate()
        return true
    }
    
    static func vibrate() {
        WKInterfaceDevice.current().play(.click)
    }
    
    //does not exist on Applw Watch
    static func startProximitySensor() {
        return
    }
    
    static func stopProximitySensor() {
        return
    }
    
    static func getBatteryLevel() -> Float {
        if #available(watchOSApplicationExtension 4.0, *) {
            return abs(WKInterfaceDevice.current().batteryLevel)
        } else {
            return 1.0
        }
    }
    
    static func startBatteryLevelMonitoring() {
        //additionally non async to enable it immediately
        if #available(watchOSApplicationExtension 4.0, *) {
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            DispatchQueue.main.async {
                WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    static func stopBatteryLevelMonitoring() {
        if #available(watchOSApplicationExtension 4.0, *) {
            DispatchQueue.main.async {
                WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    //uses background location to keep the app running in background
    @available(watchOSApplicationExtension 4.0, *)
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
    
    @available(watchOSApplicationExtension 4.0, *)
    static func stopBackgroundUsage() {
        locationManager.stopUpdatingLocation()
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
#endif
