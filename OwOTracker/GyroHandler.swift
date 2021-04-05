//
//  GyroListener.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreMotion

public class GyroHandler {
    
    var mmanager : CMMotionManager?
    static var instance : GyroHandler?
    var motionAvailable = true
    var accelerometerAvailable = true
    var gyroAvailable = true
    var magnetometerAvailable = true
    var client : UDPGyroProviderClient?
    
    private init(client: UDPGyroProviderClient) {
        mmanager = CMMotionManager()
        self.client = client
        motionAvailable = mmanager!.isDeviceMotionAvailable
        accelerometerAvailable = mmanager!.isDeviceMotionAvailable
        gyroAvailable = mmanager!.isGyroAvailable
        magnetometerAvailable = mmanager!.isMagnetometerAvailable
        
        mmanager!.deviceMotionUpdateInterval = 0.1
        mmanager!.startDeviceMotionUpdates(to: OperationQueue.main, withHandler: { (MotionData, Error) in
            let quat = MotionData!.attitude.quaternion
            let data = [Float(quat.x), Float(quat.y), Float(quat.z), Float(quat.w)]
            client.provideRot(rot: data)
        })
        
        mmanager!.accelerometerUpdateInterval = 0.1
        mmanager!.startAccelerometerUpdates(to: OperationQueue.main, withHandler: { (MotionData, Error) in
            let values = MotionData!.acceleration
            let data = [Float(values.x), Float(values.y), Float(values.z)]
            client.provideAcc(accel: data)
        })
        
        mmanager!.gyroUpdateInterval = 0.1
        mmanager!.startGyroUpdates(to: OperationQueue.main, withHandler: { (MotionData, Error) in
            let values = MotionData!.rotationRate
            let data = [Float(values.x), Float(values.y), Float(values.z)]
            client.provideGyro(gyro: data)
        })
        
        mmanager!.magnetometerUpdateInterval = 0.1
        mmanager!.startMagnetometerUpdates(to: OperationQueue.main, withHandler: { (MotionData, Error) in
            let values = MotionData!.magneticField
            let data = [Float(values.x), Float(values.y), Float(values.z)]
        })
    }
    
    static func getInstance(client: UDPGyroProviderClient) -> GyroHandler {
        if (instance == nil) {
            instance = GyroHandler(client: client)
        }
        return instance!
    }
    
    
    
}
