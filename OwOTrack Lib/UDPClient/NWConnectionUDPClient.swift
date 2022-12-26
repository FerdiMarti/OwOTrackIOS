//
//  UDPGyroProviderClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 12.12.22.
//

//This class handles the UDP communication with the server on iOS 12.0+ and watchOS 5.0+. NWConnection is not supported in lower OSs. The advantage over SwiftSocket is that the bound UDP port of the device can be set programatically.

import Foundation
import Network

let BIND_PORT_USERDEFAULTS_KEY = "bindport"

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
    
    //opens the connection to specified ip and port
    func open(cb: @escaping () -> Void) {
        loadLastPort()  // if a connection has been established before, the app tries to bind the same UDP port again because of weird behaviour of SlimeVR server.
        let params = NWParameters.udp
        if bindPort != nil {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("0.0.0.0"), port: self.bindPort!)
        }
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: params)
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                self.setLastPort()  //port is saved for next usage
                cb()
                print("State: Ready\n")
            case .setup:
                print("State: Setup\n")
            case .cancelled:
                print("State: Cancelled\n")
            case .preparing:
                print("State: Preparing\n")
            case .failed(let error):
                print("State: error \(error)\n")
            case .waiting(let error):
                print("State: Waiting \(error)\n")
                //the port we used last time might be bound already. Let's reset it
                if error.debugDescription.contains("Address already in use") {
                    self.resetLastPort()
                    self.logger.addEntry("Please try again")
                }
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
    
    //loads last used port from UserDefaults if available
    func loadLastPort() {
        if let portTmp = defaults.object(forKey: BIND_PORT_USERDEFAULTS_KEY) as? String {
            self.bindPort = NWEndpoint.Port(portTmp)
        }
    }

    //saves last used port n UserDefaults
    func setLastPort() {
        guard let bPort = self.connection?.currentPath?.localEndpoint?.debugDescription.split(separator: ":")[1] else {
            return
        }
        self.defaults.set(bPort, forKey: BIND_PORT_USERDEFAULTS_KEY)
    }
    
    //Deletes last used port from UserDefaults so that the port is chosen automatically on next connection
    func resetLastPort() {
        self.bindPort = nil
        self.defaults.removeObject(forKey: BIND_PORT_USERDEFAULTS_KEY)
    }
}
