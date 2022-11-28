//
//  AutoDiscovery.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 25.11.22.
//

import Foundation
import Network

class AutoDiscovery {

    var connection: NWConnection?
    var logger = Logger.getInstance()
    var portUDP = 35903
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
            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { (timer) in
                if self.isWaiting {
                    self.logger.addEntry("No Tracker discovered")
                    self.isWaiting = false
                    cb(true, "", "")
                }
            }
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
}
