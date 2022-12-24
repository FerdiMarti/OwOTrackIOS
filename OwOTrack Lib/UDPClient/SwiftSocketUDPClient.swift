//
//  UDPGyroProviderClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 15.12.22.
//

import Foundation
import Network

let RECEIVE_QUEUE_LABEL = "SwiftSocketReceive"

//UDP Client that uses SwiftSocket library instead of NWConnection to support iOS 9 - iOS 11
class SwiftSocketUDPClient: CompatibleUDPClient {

    var client: UDPClient?
    var logger = Logger.getInstance()
    var hostUDP = "192.168.0.10"
    var portUDP = 6969
    var receiveQueue = DispatchQueue.init(label: RECEIVE_QUEUE_LABEL)
    
    init(host: String, port: Int) {
        self.hostUDP = host
        self.portUDP = port
        self.client = UDPClient(address: hostUDP, port: Int32(portUDP))
    }
    
    func open(cb: @escaping () -> Void) {
        //no preparation needed, immediately call back
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
        //run in DispatchQueue to keep app running
        receiveQueue.async {
            guard let raw = self.client?.recv(1024*10) //not sure about the "expected size" argument, 1024*10 works fine
            else {
                cb(nil)
                return
            }
            guard let data = raw.0 else { //.0 contains actual data
                print("data == nil")
                cb(nil)
                return
            }
            let ip = raw.1 //.1 contains sender's ip address
            if (ip != self.hostUDP) {
                self.logger.addEntry("Received UDP packet from wrong host")
                cb(nil)
                return
            }
            cb(Data(data))
        }
    }
}
