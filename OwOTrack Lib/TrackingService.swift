//
//  TrackingService.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreLocation
import UIKit

let TRACKING_SERVICE_QUEUE_LABEL = "TrackingService"
let IP_USERDEFAULTS_KEY = "ip"
let PORT_USERDEFAULTS_KEY = "port"
let MAGNETOMETER_USERDEFAULTS_KEY = "useM"

//manages connection, app and UI state
public class TrackingService: NSObject, CLLocationManagerDelegate {
    var ipAdress = ""
    var port = ""
    var magnetometer = true
    var connectUI: ConnectUI?  // the UI component that needs to be updated when status changes
    let logger = Logger.getInstance()
    var gHandler: GyroHandler?
    var client: UDPGyroProviderClient?
    var batteryTimer : Timer?   //timer that triggers sending of current battery level ever 10s
    var trackingServiceQueue = DispatchQueue.init(label: TRACKING_SERVICE_QUEUE_LABEL)
    
    //Switch between hardware class depending on device type
    #if os(iOS)
    let hardware = IPhoneHardware.self
    #elseif os(watchOS)
    let hardware = WatchHardware.self
    #endif
    
    func start(ipAdress: String, port: String, magnetometer: Bool, connectUI: ConnectUI) {
        self.connectUI = connectUI
        self.ipAdress = ipAdress
        self.port = port
        self.magnetometer = magnetometer
        self.setDefaults()
        connectUI.setLoading()
        hardware.startProximitySensor()
        hardware.registerVolButtonListener(target: self)
        hardware.startBackgroundUsage(target: self)
        trackingServiceQueue.async {
            //start connection
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
                connectUI.setConnected()
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
        defaults.set(self.ipAdress, forKey: IP_USERDEFAULTS_KEY)
        defaults.set(self.port, forKey: PORT_USERDEFAULTS_KEY)
        defaults.set(self.magnetometer, forKey: MAGNETOMETER_USERDEFAULTS_KEY)
    }
    
    func stop() {
        hardware.stopProximitySensor()
        hardware.unregisterVolButtonListener(target: self)
        hardware.stopBackgroundUsage()
        stopSendingBattery()
        gHandler?.stopUpdates()
        client?.disconnectUDP()
        if (client?.isConnected) != nil && !client!.isConnected {
            connectUI?.setUnconnected()
            logger.addEntry("Disconnected")
        }
    }
    
    func toggleMagnetometerUse(use: Bool) {
        if client == nil {
            return
        }
        gHandler?.stopUpdates()
        gHandler?.startUpdates(client: client!, useMagn: use)
        connectUI?.setMagnometerToggle(use: use)
    }
    
    //handler for volume button push
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            logger.addEntry("Button Pushed")
            client?.provideButtonPushed()
        }
    }
    
    func startSendingBattery() {
        hardware.startBatteryLevelMonitoring()
        sendBatteryLevel()
        DispatchQueue.main.async {
            self.batteryTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(self.sendBatteryLevel), userInfo: nil, repeats: true)
        }
    }
    
    @objc func sendBatteryLevel() {
        let level = hardware.getBatteryLevel()
        self.client?.provideBatteryLevel(level: level)
    }
    
    func stopSendingBattery() {
        batteryTimer?.invalidate()
        hardware.stopBatteryLevelMonitoring()
    }
}
