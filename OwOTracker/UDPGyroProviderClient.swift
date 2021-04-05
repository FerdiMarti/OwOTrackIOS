//
//  UDPGyroProviderClient.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import Network

class UDPGyroProviderClient {

    var connection: NWConnection?
    var hostUDP: NWEndpoint.Host = "10.211.55.3"
    var portUDP: NWEndpoint.Port = 6969
    
    private var packetId: Int64 = 0;
    private var isConnected: Bool = false;
    public static var CURRENT_VERSION = 5;
    var lastHeartbeat: Int = 0
    
    init(host: String, port: String) {
        hostUDP = NWEndpoint.Host(host)
        portUDP = NWEndpoint.Port(port) ?? NWEndpoint.Port("6969")!
        connectToUDP()
    }

    func connectToUDP() {
        // Transmited message:
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: .udp)
        
        self.connection?.stateUpdateHandler = { (newState) in
            print("This is stateUpdateHandler:")
            switch (newState) {
            case .ready:
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
        
        self.connection?.start(queue: .global())
    }
    
    func handshake() -> Bool {
        var data = Data(capacity: 12)
        var first = Int32(bigEndian: 3)
        var second = Int64(bigEndian: 0)
        data.append(UnsafeBufferPointer(start: &first, count: 1))
        data.append(UnsafeBufferPointer(start: &second, count: 1))
        
        var tries = 0;
        while(true) {
            tries += 1;
            if (tries > 12) {
                print("Handshake timed out. Ensure that the IP address and port are correct, that the server is running and that you're connected to the same wifi network.");
                return false
            }
            sendUDP(data)
            
            self.connection?.receiveMessage { (data, context, isComplete, error) in
                if (isComplete) {
                    if (data != nil) {
                        var result = String(data: data!, encoding: .ascii)!
                        if (!result.hasPrefix(String(Unicode.Scalar(3)))) {
                            print("Handshake failed, the server did not respond correctly. Ensure everything is up-to-date and that the port is correct.");
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 1)...])
                        if (!result.hasPrefix("Hey OVR =D")) {
                            print("Handshake failed, the server did not respond correctly in the header. Ensure everything is up-to-date and that the port is correct");
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 11)...])
                        result = String(result[result.startIndex...result.startIndex])
                        let version = Int(result)!;
                        if (version != UDPGyroProviderClient.CURRENT_VERSION) {
                            print("Handshake failed, mismatching version"
                                    + "\nServer version: \(version)"
                                    + "\nClient version: \(UDPGyroProviderClient.CURRENT_VERSION)"
                                    + "\nPlease make sure everything is up to date.");
                        }
                    } else {
                        print("Data == nil")
                    }
                }
            }
            self.isConnected = true
        }
        
    }

    func sendUDP(_ content: Data) {
        self.connection?.send(content: content, completion: NWConnection.SendCompletion.contentProcessed(({ (NWError) in
            if (NWError == nil) {
                print("Data was sent to UDP")
            } else {
                print("ERROR! Error when data (Type: Data) sending. NWError: \n \(NWError!)")
            }
        })))
    }

    func receiveUDP() {
        self.connection?.receiveMessage { (data, context, isComplete, error) in
            if (isComplete) {
                print("Receive is complete")
                if (data != nil) {
                    let backToString = String(data: data!, encoding: .ascii)
                    print("Received message: \(backToString)")
                } else {
                    print("Data == nil")
                }
            }
        }
    }
    
    private func provideFloats(floats: [Float], len: Int, msgType: Int32) {
        if (!isConnected) {
            return;
        }
        var type = Int32(bigEndian: msgType)
        var id = Int64(bigEndian: packetId)
        var values = floats

        let bytes = 12 + len * 4; // 12b header (int + long)  + floats (4b each)

        var data = Data(capacity: bytes)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        data.append(UnsafeBufferPointer(start: &values, count: values.count))

        sendUDP(data)
        packetId += 1;
    }

    public func provideGyro(gyro: [Float]) {
        provideFloats(floats: gyro, len: 3, msgType: 2);
    }

    public func provideRot(rot: [Float]) {
        provideFloats(floats: rot, len: 4, msgType: 1);
    }

    public func provideAcc(accel: [Float]) {
        provideFloats(floats: accel, len: 3, msgType: 4);
    }
}
