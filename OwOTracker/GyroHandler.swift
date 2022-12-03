//
//  GyroListener.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreMotion

public class GyroHandler {
    
    var mmanager = CMMotionManager()
    static var instance : GyroHandler?
    var motionAvailable = true
    var accelerometerAvailable = true
    var gyroAvailable = true
    var magnetometerAvailable = true
    
    private init() {
        motionAvailable = mmanager.isDeviceMotionAvailable
        accelerometerAvailable = mmanager.isDeviceMotionAvailable
        gyroAvailable = mmanager.isGyroAvailable
        magnetometerAvailable = mmanager.isMagnetometerAvailable
    }
    
    func startUpdates(client: UDPGyroProviderClient, useMagn: Bool) {
        let sensorQueue = OperationQueue()
        sensorQueue.name = "SensorQueue"
        mmanager.deviceMotionUpdateInterval = 0.01
        mmanager.gyroUpdateInterval = 0.01
        mmanager.accelerometerUpdateInterval = 0.01
        mmanager.startDeviceMotionUpdates(using: useMagn ? CMAttitudeReferenceFrame.xArbitraryCorrectedZVertical : CMAttitudeReferenceFrame.xArbitraryZVertical, to: sensorQueue, withHandler: { (MotionData, Error) in
            if let md = MotionData {
                let quat = md.attitude.quaternion
                var xi = Float(quat.x).bitPattern.bigEndian
                var yi = Float(quat.y).bitPattern.bigEndian
                var zi = Float(quat.z).bitPattern.bigEndian
                var wi = Float(quat.w).bitPattern.bigEndian
                let x = Data(buffer: UnsafeBufferPointer(start: &xi, count: 1))
                let y = Data(buffer: UnsafeBufferPointer(start: &yi, count: 1))
                let z = Data(buffer: UnsafeBufferPointer(start: &zi, count: 1))
                let w = Data(buffer: UnsafeBufferPointer(start: &wi, count: 1))
                let data = [x, y, z, w]
                client.provideRot(rot: data)
            }
        })
        mmanager.startGyroUpdates(to: sensorQueue, withHandler: { (gyroData, Error) in
            if let gd = gyroData {
                var xi = Float(gd.rotationRate.x).bitPattern.bigEndian
                var yi = Float(gd.rotationRate.y).bitPattern.bigEndian
                var zi = Float(gd.rotationRate.z).bitPattern.bigEndian
                let x = Data(buffer: UnsafeBufferPointer(start: &xi, count: 1))
                let y = Data(buffer: UnsafeBufferPointer(start: &yi, count: 1))
                let z = Data(buffer: UnsafeBufferPointer(start: &zi, count: 1))
                let data = [x, y, z]
                client.provideGyro(gyro: data)
            }
        })
        mmanager.startAccelerometerUpdates(to: sensorQueue, withHandler: { (accelData, Error) in
            if let ad = accelData {
                var xi = Float(ad.acceleration.x).bitPattern.bigEndian
                var yi = Float(ad.acceleration.y).bitPattern.bigEndian
                var zi = Float(ad.acceleration.z).bitPattern.bigEndian
                let x = Data(buffer: UnsafeBufferPointer(start: &xi, count: 1))
                let y = Data(buffer: UnsafeBufferPointer(start: &yi, count: 1))
                let z = Data(buffer: UnsafeBufferPointer(start: &zi, count: 1))
                let data = [x, y, z]
                client.provideAccel(accel: data)
            }
        })
    }
    
    func stopUpdates() {
        mmanager.stopDeviceMotionUpdates()
    }
    
    static func getInstance() -> GyroHandler {
        if (instance == nil) {
            instance = GyroHandler()
        }
        return instance!
    }
}
