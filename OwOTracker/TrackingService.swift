//
//  TrackingService.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import UIKit

public class TrackingService {
    var ipAdress = ""
    var port = ""
    var magnetometer = true
    var cView: ContentView?
    let logger = Logger.getInstance()
    let defaults = UserDefaults.standard
    var gHandler: GyroHandler?
    var client: UDPGyroProviderClient?
    
    init() {}
    
    func start(ipAdress: String, port: String, magnetometer: Bool, cView: ContentView) {
        
        UIDevice.current.isProximityMonitoringEnabled = true
        
        self.cView = cView
        self.ipAdress = ipAdress
        self.port = port
        self.magnetometer = magnetometer
        cView.loading = true
        DispatchQueue.init(label: "TrackingService").async {
            self.client = UDPGyroProviderClient(host: self.ipAdress, port: self.port, service: self)
            self.client!.connectToUDP()
            var tries = 0
            while(!self.client!.isConnected && tries < 5) {
                tries += 1
                sleep(1)
            }
            self.cView!.loading = false
            if (self.client!.isConnected) {
                self.defaults.set(self.ipAdress, forKey: "ip")
                self.defaults.set(self.port, forKey: "port")
                self.logger.addEntry("Connection established")
                self.cView!.connected = true
                self.gHandler = GyroHandler.getInstance()
                self.gHandler!.startUpdates(client: self.client!, useMagn: magnetometer)
                self.client!.runListener()
            } else {
                self.stop()
                self.logger.addEntry("Connection Failed")
            }
        }
    }
    
    func stop() {
        DispatchQueue.main.async {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
        gHandler?.stopUpdates()
        client?.disconnectUDP()
        if (client?.isConnected) != nil && !client!.isConnected {
            cView?.connected = false
            logger.addEntry("Disconnected")
        }
    }
    
    func toggleMagnetometerUse(use: Bool) {
        gHandler?.stopUpdates()
        gHandler?.startUpdates(client: client!, useMagn: use)
        cView?.useMagnetometer = use
    }
}
