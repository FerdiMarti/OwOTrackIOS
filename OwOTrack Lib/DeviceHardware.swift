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
    
    @available(iOS 13.0, *)
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool
    
    static func vibrate()
    
    static func startProximitySensor()
    
    static func stopProximitySensor()
    
    static func getBatteryLevel() -> Float
    
    static func startBatteryLevelMonitoring()
    
    static func stopBatteryLevelMonitoring()
    
    @available(watchOSApplicationExtension 4.0, *)
    static func startBackgroundUsage(target: CLLocationManagerDelegate)
    
    @available(watchOSApplicationExtension 4.0, *)
    static func stopBackgroundUsage()
    
    static func getPseudoMacAddress() -> [UInt8]
}
