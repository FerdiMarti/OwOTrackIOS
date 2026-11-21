//
//  DeviceHardware.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 19.12.22.
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
    
    static func startBackgroundUsage(target: CLLocationManagerDelegate?)
    
    static func stopBackgroundUsage()
    
    static func getPseudoMacAddress() -> [UInt8]
}

//the hardware one tracking session uses. For this device it's the static DeviceHardware (StaticHardware);
//the watch's session that the iPhone relays has its own (RelayedWatchHardware)
protocol TrackerHardware {
    func registerVolButtonListener(target: NSObject)
    func unregisterVolButtonListener(target: NSObject)
    func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool
    func vibrate()
    func startProximitySensor()
    func stopProximitySensor()
    func preventAutoLock()
    func allowAutoLock()
    func getBatteryLevel() -> Float?
    func startBatteryLevelMonitoring()
    func stopBatteryLevelMonitoring()
    func startBackgroundUsage(target: CLLocationManagerDelegate?)
    func stopBackgroundUsage()
    func getPseudoMacAddress() -> [UInt8]
}

//this device's hardware for a tracking session
struct StaticHardware: TrackerHardware {
    let type: any DeviceHardware.Type

    init(_ type: any DeviceHardware.Type) {
        self.type = type
    }

    func registerVolButtonListener(target: NSObject) { type.registerVolButtonListener(target: target) }
    func unregisterVolButtonListener(target: NSObject) { type.unregisterVolButtonListener(target: target) }
    func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool { type.vibrateAdvanced(f: f, a: a, d: d) }
    func vibrate() { type.vibrate() }
    func startProximitySensor() { type.startProximitySensor() }
    func stopProximitySensor() { type.stopProximitySensor() }
    func preventAutoLock() { type.preventAutoLock() }
    func allowAutoLock() { type.allowAutoLock() }
    func getBatteryLevel() -> Float? { type.getBatteryLevel() }
    func startBatteryLevelMonitoring() { type.startBatteryLevelMonitoring() }
    func stopBatteryLevelMonitoring() { type.stopBatteryLevelMonitoring() }
    func startBackgroundUsage(target: CLLocationManagerDelegate?) { type.startBackgroundUsage(target: target) }
    func stopBackgroundUsage() { type.stopBackgroundUsage() }
    func getPseudoMacAddress() -> [UInt8] { type.getPseudoMacAddress() }
}

//something several sessions can need at the same time, like keeping the iPhone awake while it tracks and relays the watch:
//switched on by the first session that needs it and off when the last one is done
final class SharedSwitch {
    private let lock = NSLock()
    private var users = 0
    private let on: () -> Void
    private let off: () -> Void

    init(on: @escaping () -> Void, off: @escaping () -> Void) {
        self.on = on
        self.off = off
    }

    var isOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return users > 0
    }

    func acquire() {
        lock.lock()
        defer { lock.unlock() }
        users += 1
        if users == 1 {
            on()
        }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        if users == 0 {
            return
        }
        users -= 1
        if users == 0 {
            off()
        }
    }
}
