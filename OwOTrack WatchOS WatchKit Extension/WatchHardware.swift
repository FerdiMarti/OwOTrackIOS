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
    
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool  {
        vibrate()
        return true
    }
    
    static func vibrate() {
        WKInterfaceDevice.current().play(.click)
    }
    
    static func startProximitySensor() {
        return
    }
    
    static func stopProximitySensor() {
        return
    }
    
    static func getBatteryLevel() -> Float {
        return abs(WKInterfaceDevice.current().batteryLevel)
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
}
#endif
