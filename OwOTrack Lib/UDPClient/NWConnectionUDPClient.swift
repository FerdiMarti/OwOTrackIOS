//
//  UDPGyroProviderClient.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 12.12.22.
//

import Foundation
import Network

@available(iOS 12.0, *)
@available(watchOS 5.0, *)
class NWConnectionUDPClient: CompatibleUDPClient {

    var connection: NWConnection?
    var logger = Logger.getInstance()
    var hostUDP: NWEndpoint.Host = "192.168.0.10"
    var portUDP: NWEndpoint.Port = 6969
    let defaults = UserDefaults.standard
    var bindPort: NWEndpoint.Port? = nil
    
    init(host: String, port: Int) {
        self.hostUDP = NWEndpoint.Host(host)
        self.portUDP = NWEndpoint.Port(String(port)) ?? NWEndpoint.Port("6969")!
    }
    
    func open(cb: @escaping () -> Void) {
        loadLastPort()
        let params = NWParameters.udp
        if bindPort != nil {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("0.0.0.0"), port: self.bindPort!)
        }
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: params)
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                self.setLastPort()
                cb()
                print("State: Ready\n")
            case .setup:
                print("State: Setup\n")
            case .cancelled:
                print("State: Cancelled\n")
            case .preparing:
                print("State: Preparing\n")
            default:
                //the port we used last time might be bound already. Let's reset it
                self.resetLastPort()
                self.logger.addEntry("Please try again")
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
    
    func loadLastPort() {
        if let portTmp = defaults.object(forKey: "bindport") as? String {
            self.bindPort = NWEndpoint.Port(portTmp)
        }
    }

    func setLastPort() {
        guard let bPort = self.connection?.currentPath?.localEndpoint?.debugDescription.split(separator: ":")[1] else {
            return
        }
        self.defaults.set(bPort, forKey: "bindport")
    }
    
    func resetLastPort() {
        self.bindPort = nil
        self.defaults.removeObject(forKey: "bindport")
    }
}
