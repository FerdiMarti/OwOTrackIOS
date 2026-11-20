//
//  GyroListener.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreMotion

//Singleton that queries and provides sensor data
public class GyroHandler {
    
    var mmanager = CMMotionManager()
    static var instance : GyroHandler?
    var motionAvailable = false
    var accelerometerAvailable = false
    var gyroAvailable = false
    var magnetometerAvailable = false
    
    private init() {
        motionAvailable = mmanager.isDeviceMotionAvailable
        accelerometerAvailable = mmanager.isDeviceMotionAvailable
        gyroAvailable = mmanager.isGyroAvailable
        magnetometerAvailable = mmanager.isMagnetometerAvailable
    }
    
    func startUpdates(client: UDPGyroProviderClient, useMagn: Bool) {
        let sensorQueue = OperationQueue()
        sensorQueue.name = "SensorQueue"
        sensorQueue.maxConcurrentOperationCount = 1 //OperationQueue is concurrent by default; handle sensor updates one at a time, in order
        mmanager.deviceMotionUpdateInterval = 0.01
        mmanager.gyroUpdateInterval = 0.01
        mmanager.accelerometerUpdateInterval = 0.01
        mmanager.startDeviceMotionUpdates(using: useMagn ? CMAttitudeReferenceFrame.xArbitraryCorrectedZVertical : CMAttitudeReferenceFrame.xArbitraryZVertical, to: sensorQueue, withHandler: { (MotionData, Error) in
            if let md = MotionData {
                let quat = md.attitude.quaternion
                let data = [Data(bigEndian: Float(quat.x)), Data(bigEndian: Float(quat.y)), Data(bigEndian: Float(quat.z)), Data(bigEndian: Float(quat.w))]
                client.provideRot(rot: data)
            }
        })
        mmanager.startGyroUpdates(to: sensorQueue, withHandler: { (gyroData, Error) in
            if let gd = gyroData {
                let rate = gd.rotationRate
                let data = [Data(bigEndian: Float(rate.x)), Data(bigEndian: Float(rate.y)), Data(bigEndian: Float(rate.z))]
                client.provideGyro(gyro: data)
            }
        })
        mmanager.startAccelerometerUpdates(to: sensorQueue, withHandler: { (accelData, Error) in
            if let ad = accelData {
                let accel = ad.acceleration
                let data = [Data(bigEndian: Float(accel.x)), Data(bigEndian: Float(accel.y)), Data(bigEndian: Float(accel.z))]
                client.provideAccel(accel: data)
            }
        })
    }
    
    func stopUpdates() {
        mmanager.stopDeviceMotionUpdates()
        mmanager.stopGyroUpdates()
        mmanager.stopAccelerometerUpdates()
    }
    
    static func getInstance() -> GyroHandler {
        if (instance == nil) {
            instance = GyroHandler()
        }
        return instance!
    }
}
