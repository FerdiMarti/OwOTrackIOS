//
//  TrackingService.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation

public class TrackingService {
    var ipAdress = ""
    var port = ""
    var cView: ContentView
    let logger = Logger.getInstance()
    let defaults = UserDefaults.standard
    
    init(ipAdress: String, port: String, cView: ContentView) {
        self.ipAdress = ipAdress
        self.port = port
        self.cView = cView
    }
    
    func start() {
        cView.loading = true
        DispatchQueue.init(label: "TrackingService").async {
            let client = UDPGyroProviderClient(host: self.ipAdress, port: self.port)
            client.connectToUDP()
            var tries = 0
            while(!client.isConnected && tries < 5) {
                tries += 1
                sleep(1)
            }
            self.cView.loading = false
            if (client.isConnected) {
                self.defaults.set(self.ipAdress, forKey: "ip")
                self.defaults.set(self.port, forKey: "port")
                self.logger.addEntry("Connection established")
                self.cView.connected = true
                let handler = GyroHandler.getInstance()
                handler.startUpdates(client: client)
                client.runListener()
            } else {
                self.logger.addEntry("Connection Failed")
            }
        }
    }
}
