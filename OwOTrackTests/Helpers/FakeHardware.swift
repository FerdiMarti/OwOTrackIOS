//
//  FakeHardware.swift
//  OwOTrackTests
//

import Foundation
import CoreLocation
@testable import OwOTrack_iOS

//stands in for the iPhone hardware: records what the app switches on and off, without touching anything real
final class FakeHardware: DeviceHardware {
    //the MAC address the live tests have always used, so SlimeVR shows the same test tracker
    static let testMac: [UInt8] = [0x02, 0x0E, 0x57, 0x00, 0x00, 0x01]
    static let batteryLevel: Float = 0.8

    private static let lock = NSLock()
    private static var recorded: [String] = []

    static var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func reset() {
        lock.lock()
        recorded.removeAll()
        lock.unlock()
    }

    private static func record(_ event: String) {
        lock.lock()
        recorded.append(event)
        lock.unlock()
    }

    static func registerVolButtonListener(target: NSObject) { record("volume buttons on") }
    static func unregisterVolButtonListener(target: NSObject) { record("volume buttons off") }
    static func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        record("vibrate f=\(f) a=\(a) d=\(d)")
        return true
    }
    static func vibrate() { record("vibrate") }
    static func startProximitySensor() {}
    static func stopProximitySensor() {}
    static func preventAutoLock() { record("auto-lock prevented") }
    static func allowAutoLock() { record("auto-lock allowed") }
    static func getBatteryLevel() -> Float? { batteryLevel }
    static func startBatteryLevelMonitoring() {}
    static func stopBatteryLevelMonitoring() {}
    static func startBackgroundUsage(target: CLLocationManagerDelegate) { record("background started") }
    static func stopBackgroundUsage() { record("background stopped") }
    static func getPseudoMacAddress() -> [UInt8] { testMac }
}
