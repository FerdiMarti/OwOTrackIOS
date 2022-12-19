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
    var gHandler: GyroHandler?
    var client: UDPGyroProviderClient?
    var audioSession = AVAudioSession.sharedInstance()
    let locationManager = CLLocationManager()
    var batteryTimer : Timer?
    var trackingServiceQueue = DispatchQueue.init(label: "TrackingService")
    
    func start(ipAdress: String, port: String, magnetometer: Bool, cvc: ConnectViewController) {
        self.cvc = cvc
        self.ipAdress = ipAdress
        self.port = port
        self.magnetometer = magnetometer
        self.setDefaults()
        cvc.setLoading()
        self.registerVolButtonListener()
        startBackgroundUsage()
        trackingServiceQueue.async {
            self.client = UDPGyroProviderClient(host: self.ipAdress, port: self.port, service: self)
            if self.client == nil {
                self.logger.addEntry("Initializing Connection Failed")
                return
            }
            self.client!.connectToUDP()
            var waited = 0
            while(!self.client!.isConnected && waited < 5) {
                waited += 1
                sleep(1)
            }
            if (self.client!.isConnected) {
                self.logger.addEntry("Connection established")
                cvc.setConnected()
                self.startSendingBattery()
                self.gHandler = GyroHandler.getInstance()
                self.gHandler?.startUpdates(client: self.client!, useMagn: magnetometer)
                self.client?.provideMagnetometerUse(enabled: self.magnetometer)
            } else {
                self.logger.addEntry("Handshake Failed")
                self.logger.addEntry("\n Connection timed out. Ensure IP and port are correct, that the server is running and not blocked by Windows Firewall (try changing your network type to private in Windows, or running the firewall script) or blocked by router, and that you're connected to the same network (you may need to disable Mobile Data) \n")
                self.logger.addEntry("Connecting Failed")
                self.stop()
            }
        }
    }
    
    func setDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(self.ipAdress, forKey: "ip")
        defaults.set(self.port, forKey: "port")
        defaults.set(self.magnetometer, forKey: "useM")
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
//        trackingServiceQueue.suspend()
//        trackingServiceQueue.finalize()
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
            self.batteryTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(self.sendBatteryLevel), userInfo: nil, repeats: true)
        }
    }
    
    @objc func sendBatteryLevel() {
        let level = self.getBatteryLevel()
        self.client?.provideBatteryLevel(level: level)
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
