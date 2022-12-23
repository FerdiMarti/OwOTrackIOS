//
//  AutoDiscovery.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 25.11.22.
//

import Foundation
import Network

class AutoDiscovery {

    var logger = Logger.getInstance()
    var broadcastConnection: UDPBroadcastConnection?
    var isWaiting = false
    
    init() {
       
    }
    
    func setupBroadcast(cb: @escaping (Bool ,String, String) -> Void) {
        do {
            broadcastConnection = try UDPBroadcastConnection(
                port: 35903,
                handler: { [weak self] (ipAddress: String, port: Int, response: Data) -> Void in
                    let str = String(data: response, encoding: .ascii)!
                    let tPort = str.split(separator: ":")[0]
                    self!.logger.addEntry("Found Tracker: \(ipAddress):\(tPort)")
                    self?.isWaiting = false
                    cb(false, ipAddress, tPort.description)
                },
                errorHandler: { [weak self] (error) in
                    guard let self = self else { return }
                    self.logger.addEntry(error.localizedDescription)
                    print(error)
                    self.isWaiting = false
                    cb(true, "", "")
                })
        } catch {
            self.isWaiting = false
            if let connectionError = error as? UDPBroadcastConnection.ConnectionError {
                logger.addEntry(connectionError.localizedDescription)
                print(connectionError)
                cb(true, "", "")
            }
            else {
                logger.addEntry("Error: \(error)\n")
                print("Error: \(error)\n")
                cb(true, "", "")
            }
        }
    }
    
    func sendDiscovery(cb: @escaping (Bool, String, String) -> Void) {
        logger.reset()
        setupBroadcast(cb: cb)
        do {
            logger.addEntry("Attempting Discovery")
            isWaiting = true
            try broadcastConnection!.sendBroadcast("DISCOVERY")
            Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(self.checkSuccess), userInfo: cb, repeats: false)
        } catch {
            if let connectionError = error as? UDPBroadcastConnection.ConnectionError {
                logger.addEntry(connectionError.localizedDescription)
                print(connectionError)
                cb(true, "", "")
            }
            else {
                logger.addEntry("Error: \(error)\n")
                print("Error: \(error)\n")
                cb(true, "", "")
            }
        }
    }
    
    @objc func checkSuccess(sender: Timer) {
        if self.isWaiting {
            self.logger.addEntry("No Tracker discovered")
            self.logger.addEntry("Discovery does not work with SlimeVR")
            self.isWaiting = false
            let cb = sender.userInfo as! (Bool, String, String) -> Void
            cb(true, "", "")
        }
    }
}
