//
//  TrackingService.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import UIKit
import AVFoundation
import CoreLocation

public class TrackingService: NSObject, CLLocationManagerDelegate {
    var ipAdress = ""
    var port = ""
    var magnetometer = true
    var cvc: ConnectViewController?
    let logger = Logger.getInstance()
    let defaults = UserDefaults.standard
    var gHandler: GyroHandler?
    var client: UDPGyroProviderClient?
    var audioSession = AVAudioSession.sharedInstance()
    let locationManager = CLLocationManager()
    var batteryTimer : Timer?
    
    func start(ipAdress: String, port: String, magnetometer: Bool, cvc: ConnectViewController) {
        self.cvc = cvc
        self.ipAdress = ipAdress
        self.port = port
        self.magnetometer = magnetometer
        cvc.setLoading()
        self.registerVolButtonListener()
        startBackgroundUsage()
        DispatchQueue.init(label: "TrackingService").async {
            self.client = UDPGyroProviderClient(host: self.ipAdress, port: self.port, service: self)
            if self.client == nil {
                self.logger.addEntry("Initializing Connection Failed")
                return
            }
            self.client!.connectToUDP()
            var tries = 0
            while(!self.client!.isConnected && tries < 5) {
                tries += 1
                sleep(1)
            }
            if (self.client!.isConnected) {
                self.defaults.set(self.ipAdress, forKey: "ip")
                self.defaults.set(self.port, forKey: "port")
                self.defaults.set(self.magnetometer, forKey: "useM")
                self.logger.addEntry("Connection established")
                cvc.setConnected()
                self.startSendingBattery()
                self.gHandler = GyroHandler.getInstance()
                self.gHandler?.startUpdates(client: self.client!, useMagn: magnetometer)
                self.client!.runListener()
                self.client?.provideMagnetometerUse(enabled: self.magnetometer)
            } else {
                self.stop()
                self.logger.addEntry("Connection Failed")
            }
        }
    }
    
    func stop() {
        stopProximitySensor()
        stopSendingBattery()
        if audioSession.observationInfo != nil {
            audioSession.removeObserver(self, forKeyPath: "outputVolume")
        }
        do {
            try audioSession.setActive(false)
        } catch {
            print("audioSession could not be deinitialized")
        }
        locationManager.stopUpdatingLocation()
        gHandler?.stopUpdates()
        client?.disconnectUDP()
        if (client?.isConnected) != nil && !client!.isConnected {
            cvc?.setUnconnected()
            logger.addEntry("Disconnected")
        }
    }
    
    func toggleMagnetometerUse(use: Bool) {
        if client == nil {
            return
        }
        gHandler?.stopUpdates()
        gHandler?.startUpdates(client: client!, useMagn: use)
        cvc?.setMagnometerToggle(use: use)
    }
    
    func registerVolButtonListener() {
        do {
            try audioSession.setActive(true)
        } catch {
            print("audioSession could not be initialized")
        }
        audioSession.addObserver(self, forKeyPath: "outputVolume", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            client?.buttonPushed()
        }
    }
    
    func startBackgroundUsage() {
        locationManager.requestAlwaysAuthorization()
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
                case .notDetermined, .restricted, .denied:
                    startProximitySensor()
                case .authorizedAlways, .authorizedWhenInUse:
                    print("Access")
                @unknown default:
                break
            }
        } else {
                startProximitySensor()
        }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 99999
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        startProximitySensor()
    }
    
    func startProximitySensor() {
        UIDevice.current.isProximityMonitoringEnabled = true
    }
    
    func stopProximitySensor() {
        DispatchQueue.main.async {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }
    
    func startBatterLevelMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func startSendingBattery() {
        self.startBatterLevelMonitoring()
        let level = self.getBatteryLevel()
        client?.provideBatteryLevel(level: level)
        DispatchQueue.main.async {
            self.batteryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { (timer) in
                let level = self.getBatteryLevel()
                self.client?.provideBatteryLevel(level: level)
            }
        }
    }
    
    func stopSendingBattery() {
        batteryTimer?.invalidate()
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }
    
    func getBatteryLevel() -> Float {
        return abs(UIDevice.current.batteryLevel)
    }
}
