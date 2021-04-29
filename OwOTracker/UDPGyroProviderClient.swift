//
//  UDPGyroProviderClient.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import Network
import CoreHaptics
import AudioToolbox

class UDPGyroProviderClient {

    var connection: NWConnection?
    var logger = Logger.getInstance()
    var hostUDP: NWEndpoint.Host = "10.211.55.3"
    var portUDP: NWEndpoint.Port = 6969
    
    private var packetId: Int64 = 0
    var isConnected: Bool = false
    var lastHeartbeat: Double = 0
    var service: TrackingService
    
    public static var CURRENT_VERSION = 5
    
    init(host: String, port: String, service: TrackingService) {
        self.hostUDP = NWEndpoint.Host(host)
        self.portUDP = NWEndpoint.Port(port) ?? NWEndpoint.Port("6969")!
        self.service = service
    }
    
    func disconnectUDP() {
        logger.addEntry("Disconnecting Client")
        connection?.cancel()
        isConnected = false
    }

    func connectToUDP() {
        logger.reset()
        logger.addEntry("Attempting Connection")
        isConnected = false
        packetId = 0
        lastHeartbeat = 0
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: .udp)
        
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                self.logger.addEntry("Connection Ready")
                self.logger.addEntry("Attempting Handshake")
                self.handshake()
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
    
    func handshake() {
        var data = Data(capacity: 12)
        var first = Int32(bigEndian: 3)
        var second = Int64(bigEndian: 0)
        data.append(UnsafeBufferPointer(start: &first, count: 1))
        data.append(UnsafeBufferPointer(start: &second, count: 1))
        
        var tries = 0;
        while(!isConnected && tries <= 12) {
            tries += 1;
            sendUDP(data)
            self.connection?.receiveMessage { (data, context, isComplete, error) in
                if (isComplete && !self.isConnected) {
                    if (data != nil) {
                        var result = String(data: data!, encoding: .ascii)!
                        if (!result.hasPrefix(String(Unicode.Scalar(3)))) {
                            self.logger.addEntry("Handshake Failed")
                            self.service.stop()
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 1)...])
                        if (!result.hasPrefix("Hey OVR =D")) {
                            self.logger.addEntry("Handshake Failed")
                            self.service.stop()
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 11)...])
                        result = String(result[result.startIndex...result.startIndex])
                        let version = Int(result)!;
                        if (version != UDPGyroProviderClient.CURRENT_VERSION) {
                            self.logger.addEntry("Handshake Failed")
                            self.service.stop()
                            return
                        }
                        self.logger.addEntry("Handshake Succeded")
                        self.isConnected = true
                        self.lastHeartbeat = Date().timeIntervalSince1970;
                        return
                    } else {
                        self.logger.addEntry("Handshake Failed")
                        self.service.stop()
                        return
                    }
                }
            }
        }
        self.logger.addEntry("Handshake Failed")
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

    func receiveUDP(cb: @escaping (Data) -> Void) {
        self.connection?.receiveMessage { (data, context, isComplete, error) in
            if (isComplete) {
                if (data != nil) {
                    cb(data!)
                } else {
                    print("Data == nil")
                }
            }
        }
    }
    
    func runListener() {
        while (self.isConnected) {
            if !self.checkConnection() {
                return
            }
            sleep(1)
            self.receiveUDP(cb: { data in
                self.lastHeartbeat = Date().timeIntervalSince1970;
                var msgType : UInt8 = 0
                data.copyBytes(to: &msgType, count: 4)
                if msgType == 1 {
                    // heartbeat
                } else if msgType == 2 {
                    // vibrate
                    var restData = data.advanced(by: 4)
                    let duration = Float(bitPattern: UInt32(bigEndian: restData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
                    restData = restData.advanced(by: 4)
                    let frequency = Float(bitPattern: UInt32(bigEndian: restData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
                    restData = restData.advanced(by: 4)
                    let amplitude = Float(bitPattern: UInt32(bigEndian: restData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
                    /* if self.vibrateAdvanced(f: frequency, a: amplitude, d: duration) == false {
                        self.vibrate()
                    } */
                    self.vibrate()
                } else if msgType == 7 {
                    let restData = data.advanced(by: 4)
                    let m = String(UInt32(bigEndian: restData.prefix(1).withUnsafeBytes { $0.load(as: UInt32.self) }))
                    self.service.toggleMagnetometerUse(use: m == "y")
                } else {
                    print("Unknown message type \(msgType)")
                }
            })
        }
    }
    
    func checkConnection() -> Bool {
        if !isConnected {
            return false
        }
        let time = Date().timeIntervalSince1970
        let timeDiff = time - lastHeartbeat
        if timeDiff > 10 {
            logger.addEntry("Connection with server lost")
            service.stop()
            return false
        }
        return true
    }
    
    private func provideFloats(floats: [Data], len: Int, msgType: Int32) {
        if (!isConnected) {
            return;
        }
        var type = Int32(bigEndian: msgType)
        var id = Int64(bigEndian: packetId)

        let bytes = 12 + len * 4;

        var data = Data(capacity: bytes)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        for elem in floats {
            data.append(elem)
        }

        sendUDP(data)
        packetId += 1;
    }

    public func provideRot(rot: [Data]) {
        provideFloats(floats: rot, len: 4, msgType: 1);
    }
    
    public func provideMagnetometerUse(enabled: Bool) {
        if (!isConnected) {
            return;
        }
        
        let len = 12 + 2;
        var type = Int32(bigEndian: 5)
        var id = Int64(bigEndian: packetId)
        let mstr = enabled ? "y" : "n"
        var m = Int8(bigEndian: Int8(mstr)!)
        
        var data = Data(capacity: len)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        data.append(UnsafeBufferPointer(start: &m, count: 1))
        
        sendUDP(data)
        packetId += 1;
    }
    
    func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        // make sure that the device supports haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        var engine : CHHapticEngine
        do {
            engine = try CHHapticEngine()
            try engine.start(completionHandler: { (error) in
                var events = [CHHapticEvent]()
        
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                events.append(event)
                
                do {
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: 0)
                    print("done")
                } catch {
                    print("Failed to play pattern: \(error.localizedDescription).")
                }
                
            })
        } catch {
            return false
        }
        return true
    }
    
    func vibrate() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
}
