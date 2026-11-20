//
//  DeviceHardware.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 21.12.22.
//

import Foundation
import CoreLocation

//Protocol to abstract static functions to device hardware on iOS or watchOS
protocol DeviceHardware {
    
    static func unregisterVolButtonListener(target: NSObject)
    
    static func registerVolButtonListener(target: NSObject)
    
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool
    
    static func vibrate()
    
    static func startProximitySensor()
    
    static func stopProximitySensor()

    //keeps the device from locking automatically while tracking
    static func preventAutoLock()

    static func allowAutoLock()
    
    //battery level from 0 to 1, or nil while it's unknown
    static func getBatteryLevel() -> Float?
    
    static func startBatteryLevelMonitoring()
    
    static func stopBatteryLevelMonitoring()
    
    static func startBackgroundUsage(target: CLLocationManagerDelegate)
    
    static func stopBackgroundUsage()
    
    static func getPseudoMacAddress() -> [UInt8]
}
