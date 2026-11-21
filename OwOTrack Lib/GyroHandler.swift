//
//  GyroListener.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreMotion

//receives motion readings as big-endian floats: rotation (x y z w), rotation rate and acceleration (x y z).
//The client sends them to the server; on the watch, the relay sends them to the iPhone
protocol MotionSink: AnyObject {
    func provideRot(rot: [Data])
    func provideGyro(gyro: [Data])
    func provideAccel(accel: [Data])
}

//where a tracking session gets its motion readings: this device's sensors (GyroHandler),
//or for the watch's session that the iPhone relays, the watch's readings (RelayedWatchMotion)
protocol MotionSource: AnyObject {
    //whether the orientation can be corrected with the magnetometer
    var magnetometerCorrectionAvailable: Bool { get }
    func startUpdates(sink: MotionSink, useMagn: Bool)
    func stopUpdates()
}

//Singleton that queries and provides sensor data
public class GyroHandler: MotionSource {
    
    var mmanager = CMMotionManager()
    static var instance : GyroHandler?
    var motionAvailable = false
    var accelerometerAvailable = false
    var gyroAvailable = false
    var magnetometerAvailable = false
    //whether the orientation can be corrected with the magnetometer (the mode "Use Magnetometer" switches on)
    var magnetometerCorrectionAvailable = false

    private init() {
        motionAvailable = mmanager.isDeviceMotionAvailable
        accelerometerAvailable = mmanager.isAccelerometerAvailable
        gyroAvailable = mmanager.isGyroAvailable
        magnetometerAvailable = mmanager.isMagnetometerAvailable
        magnetometerCorrectionAvailable = CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryCorrectedZVertical)
        #if DEBUG
        //App Store screenshots come from the simulator, which has no motion sensors: show them like on a real device
        if ConnectionModel.screenshotAction != nil {
            motionAvailable = true
            accelerometerAvailable = true
            gyroAvailable = true
            magnetometerAvailable = true
        }
        #endif
    }
    
    func startUpdates(sink client: MotionSink, useMagn: Bool) {
        let sensorQueue = OperationQueue()
        sensorQueue.name = "SensorQueue"
        sensorQueue.maxConcurrentOperationCount = 1 //OperationQueue is concurrent by default; handle sensor updates one at a time, in order
        #if os(watchOS)
        //50 Hz: the watch's readings reach the server through the iPhone 20 times a second, the newest of each kind,
        //so measuring faster would only cost battery
        let interval = 0.02
        #else
        let interval = 0.01
        #endif
        mmanager.deviceMotionUpdateInterval = interval
        mmanager.gyroUpdateInterval = interval
        mmanager.accelerometerUpdateInterval = interval
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
