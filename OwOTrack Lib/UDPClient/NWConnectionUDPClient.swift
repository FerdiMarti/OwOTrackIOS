//
//  UDPGyroProviderClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 12.12.22.
//

//This class handles the UDP communication with the server using NWConnection, which also lets the app choose the device's bound UDP port.

import Foundation
import Network

let BIND_PORT_USERDEFAULTS_KEY = "bindport"

class NWConnectionUDPClient: CompatibleUDPClient {

    var connection: NWConnection?
    var hostUDP: NWEndpoint.Host = "192.168.0.10"
    var portUDP: NWEndpoint.Port = 6969
    let defaults = UserDefaults.standard
    var bindPort: NWEndpoint.Port? = nil
    
    //where the local port of the last connection is saved: the app's own session and the watch's relayed session each keep theirs
    let portKey: String

    init(host: String, port: Int, portKey: String = BIND_PORT_USERDEFAULTS_KEY) {
        self.portKey = portKey
        self.hostUDP = NWEndpoint.Host(host)
        self.portUDP = NWEndpoint.Port(String(port)) ?? NWEndpoint.Port("6969")!
    }
    
    //opens the connection to specified ip (or computer name) and port
    func open(cb: @escaping () -> Void, onProblem: @escaping (ConnectionProblem) -> Void) {
        loadLastPort()  // if a connection has been established before, the app tries to bind the same UDP port again because of weird behaviour of SlimeVR server.
        let params = NWParameters.udp
        //IPv4 only: a computer name can also resolve to IPv6 addresses, which the old owoTrack driver doesn't listen on
        //and the rest of the app doesn't use (the local port is bound to the IPv4 address 0.0.0.0)
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        if bindPort != nil {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("0.0.0.0"), port: self.bindPort!)
        }
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: params)
        var wasReady = false    //only touched by the state handler, which runs on the connection's queue
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                self.setLastPort()  //port is saved for next usage
                print("State: Ready\n")
                //the state can go ready -> waiting -> ready, e.g. when the Wi-Fi drops briefly.
                //only start once: a second call would add another listener and handshake
                if !wasReady {
                    wasReady = true
                    cb()
                }
            case .setup:
                print("State: Setup\n")
            case .cancelled:
                print("State: Cancelled\n")
            case .preparing:
                print("State: Preparing\n")
            case .failed(let error):
                print("State: error \(error)\n")
                onProblem(ConnectionProblem(reason: self.unknownNameReason(error) ?? "Connection failed: \(self.describe(error))", fatal: true))
            case .waiting(let error):
                print("State: Waiting \(error)\n")
                //the port we used last time might be bound already. Let's reset it
                if error.debugDescription.contains("Address already in use") {
                    self.resetLastPort()
                    onProblem(ConnectionProblem(reason: "The network port of the last connection is still in use. Please try again", fatal: false))
                } else {
                    onProblem(self.waitingProblem(error))
                }
            default:
                print("ERROR! State not defined!\n")
            }
        }
        self.connection?.start(queue: DispatchQueue(label: "UDPConnection"))
    }

    //a readable reason why the connection is waiting instead of ready
    private func waitingProblem(_ error: NWError) -> ConnectionProblem {
        if connection?.currentPath?.unsatisfiedReason == .localNetworkDenied {
            return ConnectionProblem(reason: "Local network access is denied. Allow it in Settings → Privacy & Security → Local Network → OwOTrack",
                                     fatal: false, localNetworkDenied: true)
        }
        return ConnectionProblem(reason: unknownNameReason(error) ?? "Can't reach the server: \(describe(error))", fatal: false)
    }

    //a computer name that couldn't be looked up (else iOS only gives an error number)
    private func unknownNameReason(_ error: NWError) -> String? {
        if case .dns = error {
            return "Can't find a computer named \"\(hostUDP)\" on the network. Check the name, or enter its IP address instead"
        }
        return nil
    }

    private func describe(_ error: NWError) -> String {
        if case .posix(let code) = error {
            return String(cString: strerror(code.rawValue))     //e.g. "Network is down"
        }
        return error.localizedDescription
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
        if let portTmp = defaults.object(forKey: portKey) as? String {
            self.bindPort = NWEndpoint.Port(portTmp)
        }
    }

    //saves last used port in UserDefaults. read from the endpoint itself, not its debug text, so it can't crash and works for IPv4 and IPv6.
    //saved as text like before, so a port saved by an older version still loads
    func setLastPort() {
        guard case .hostPort(_, let port) = self.connection?.currentPath?.localEndpoint else {
            return
        }
        self.defaults.set(String(port.rawValue), forKey: portKey)
    }
    
    //Deletes last used port from UserDefaults so that the port is chosen automatically on next connection
    func resetLastPort() {
        self.bindPort = nil
        self.defaults.removeObject(forKey: portKey)
    }
}
