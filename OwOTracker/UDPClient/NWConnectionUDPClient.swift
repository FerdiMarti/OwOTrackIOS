//
//  UDPGyroProviderClient.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 12.12.22.
//

import Foundation
import Network

@available(iOS 12.0, *)
class NWConnectionUDPClient: CompatibleUDPClient {

    var connection: NWConnection?
    var logger = Logger.getInstance()
    var hostUDP: NWEndpoint.Host = "192.168.0.10"
    var portUDP: NWEndpoint.Port = 6969
    
    init(host: String, port: Int) {
        self.hostUDP = NWEndpoint.Host(host)
        self.portUDP = NWEndpoint.Port(String(port)) ?? NWEndpoint.Port("6969")!
    }
    
    func open(cb: @escaping () -> Void) {
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: .udp)
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                cb()
                print("State: Ready\n")
            case .setup:
                print("State: Setup\n")
            case .cancelled:
                print("State: Cancelled\n")
            case .preparing:
                print("State: Preparing\n")
            default:
                print("ERROR! State not defined!\n")
            }
        }
        self.connection?.start(queue: DispatchQueue(label: "UDPConnection"))
    }
    
    func close() {
        connection?.cancel()
    }

    func sendUDP(_ content: Data) {
        self.connection?.send(content: content, completion: NWConnection.SendCompletion.contentProcessed(({ (NWError) in
            if (NWError == nil) {
                //print("Data was sent to UDP")
            } else {
                print("ERROR! Error when data (Type: Data) sending. NWError: \n \(NWError!)")
            }
        })))
    }

    func receiveUDP(cb: @escaping (Data?) -> Void) {
        self.connection?.receiveMessage { (data, context, isComplete, error) in
            if (error != nil) {
                print("Error while receiving: \(error!)")
                cb(nil)
                return
            }
            
            if (isComplete) {
                if (data != nil) {
                    cb(data)
                } else {
                    print("Data == nil")
                    cb(nil)
                }
            }
        }
    }
}
