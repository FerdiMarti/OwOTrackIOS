//
//  UDPGyroProviderClient.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 15.12.22.
//

import Foundation
import Network

class SwiftSocketUDPClient: CompatibleUDPClient {

    var client: UDPClient?
    var logger = Logger.getInstance()
    var hostUDP = "10.211.55.3"
    var portUDP = 6969
    
    init(host: String, port: Int) {
        self.hostUDP = host
        self.portUDP = port
        self.client = UDPClient(address: hostUDP, port: Int32(portUDP))
    }
    
    func open(cb: @escaping () -> Void) {
        cb()
    }
    
    func close() {
        self.client?.close()
    }

    func sendUDP(_ content: Data) {
        switch self.client?.send(data: content) {
            case .success:
                return
            case .failure(let error):
                print("ERROR! Error when data (Type: Data) sending. error: \n \(error)")
            default:
                return
        }
    }
    
    func receiveUDP(cb: @escaping (Data?) -> Void) {
        guard let raw = self.client?.recv(1024*10)
        else {
            cb(nil)
            return
        }
        let ip = raw.1
        if (ip != self.hostUDP) {
            logger.addEntry("Received UDP packet from wrong host")
            cb(nil)
            return
        }
        guard let data = raw.0 else {
            print("data == nil")
            cb(nil)
            return
        }
        cb(Data(data))
    }
}
