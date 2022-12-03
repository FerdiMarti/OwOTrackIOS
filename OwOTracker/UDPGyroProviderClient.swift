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

class PacketTypes {
    static let HEARTBEAT = 0;
    static let ROTATION = 1;
    static let GYRO = 2;
    static let HANDSHAKE = 3;
    static let ACCEL = 4;
    static let PING_PONG = 10;
    static let BATTERY_LEVEL = 12;
    static let BUTTON_PUSHED = 60;
    static let SEND_MAG_STATUS = 61;
    static let CHANGE_MAG_STATUS = 62;
    static let RECEIVE_HEARTBEAT = 1;
    static let RECEIVE_VIBRATE = 2;
}

class UDPGyroProviderClient {

    var connection: NWConnection?
    var logger = Logger.getInstance()
    var hostUDP: NWEndpoint.Host = "10.211.55.3"
    var portUDP: NWEndpoint.Port = 6969
    
    private var packetId: Int64 = 0
    var isConnected: Bool = false
    var lastHeartbeat: Double = 0
    var service: TrackingService
    var connectionCheckTimer : Timer?
    
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
        connectionCheckTimer?.invalidate()
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
    
    func buildHeaderInfo(slime: Bool) -> Data {
        var len = 12
        if slime { len += 36 + 9 }
        
        var data = Data(capacity: len)
        
        var first = Int32(bigEndian: 3)
        var second = Int64(bigEndian: 0)
        data.append(UnsafeBufferPointer(start: &first, count: 1))
        data.append(UnsafeBufferPointer(start: &second, count: 1))
        
        if !slime {
            return data
        }
        
        var boardType = Int32(bigEndian: 0)
        var imuType = Int32(bigEndian: 0)
        var mcuType = Int32(bigEndian: 0)
        var imuInfo : [Int32] = [0, 0, 0]
        var firmwareBuild = Int32(bigEndian: 8)
        var firmware = "owoTrack8" // 9 bytes
        var firmwareData = Data(firmware.utf8)
        var firmwareLength : UInt8 = UInt8(firmware.count)
        var pseudoMac : [UInt8] = [79, 54, 74, 24, 71, 37]
        data.append(UnsafeBufferPointer(start: &boardType, count: 1))
        data.append(UnsafeBufferPointer(start: &imuType, count: 1))
        data.append(UnsafeBufferPointer(start: &mcuType, count: 1))
        for i in imuInfo {
            var d = i
            data.append(UnsafeBufferPointer(start: &d, count: 1))
        }
        data.append(UnsafeBufferPointer(start: &firmwareBuild, count: 1))
        data.append(firmwareLength)
        data.append(firmwareData)
        for i in pseudoMac {
            data.append(i)
        }
        data.append(UInt8(0xff))
        
        return data
    }
    
    func handshake() {
        var tries = 0;
        while(!isConnected && tries <= 12) {
            // if the user is running an old version of owoTrackVR driver,
            // recvfrom() will fail as the max packet length the old driver
            // supported was around 28 bytes. to maintain backwards
            // compatibility the slime extensions are not sent after a
            // certain number of failures
            let sendSlimeExtensions = (tries < 7)
            let sendData = buildHeaderInfo(slime: sendSlimeExtensions)
            print(sendData)
            print(String(data: sendData, encoding: .ascii))
            
            tries += 1;
            sendUDP(sendData)
            self.connection?.receiveMessage { (data, context, isComplete, error) in
                if (isComplete && !self.isConnected) {
                    if (data != nil) {
                        var result = String(data: data!, encoding: .ascii)!
                        if (!result.hasPrefix(String(Unicode.Scalar(3)))) {
                            self.logger.addEntry("Handshake Failed")
                            self.logger.addEntry("The server did not respond correctly. Ensure everything is up-to-date and that the port is correct.")
                            self.service.stop()
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 1)...])
                        if (!result.hasPrefix("Hey OVR =D")) {
                            self.logger.addEntry("Handshake Failed")
                            self.logger.addEntry("The server did not respond correctly in the header. Ensure everything is up-to-date and that the port is correct.")
                            self.service.stop()
                            return
                        }
                        result = String(result[result.index(result.startIndex, offsetBy: 11)...])
                        result = String(result[result.startIndex...result.startIndex])
                        let version = Int(result)!;
                        if (version != UDPGyroProviderClient.CURRENT_VERSION) {
                            self.logger.addEntry("Handshake Failed")
                            self.logger.addEntry("Handshake failed, mismatching version"
                                                 + "\nServer version: \(version)"
                                                 + "\nClient version: \(UDPGyroProviderClient.CURRENT_VERSION)"
                                                 + "\nPlease make sure everything is up to date.")
                            self.service.stop()
                            return
                        }
                        self.logger.addEntry("Handshake Succeded")
                        if !sendSlimeExtensions {
                            self.logger.addEntry("Your overlay appears out-of-date with no non-fatal support for longer packet lengths, please update it")
                        }
                        self.successfulHandshake()
                        return
                    } else {
                        self.logger.addEntry("Handshake Failed")
                        self.logger.addEntry("Connection timed out. Ensure IP and port are correct, that the server is running and not blocked by Windows Firewall (try changing your network type to private in Windows, or running the firewall script) or blocked by router, and that you're connected to the same network (you may need to disable Mobile Data)")
                        self.service.stop()
                        return
                    }
                }
            }
        }
        self.logger.addEntry("Handshake Failed")
    }
    
    func successfulHandshake() {
        self.isConnected = true
        self.lastHeartbeat = Date().timeIntervalSince1970;
        DispatchQueue.main.async {
            self.connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (timer) in
                self.checkConnection()
            }
        }
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
            if (error != nil) {
                print("Error while receiving: \(error!)")
                return
            }
            
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
        self.receiveUDP(cb: { data in
            self.processReceivedData(data: data)
            if self.isConnected {
                if !self.checkConnection() {
                    return
                }
                self.runListener()
            }
        })
    }
    
    func processReceivedData(data: Data) {
        self.lastHeartbeat = Date().timeIntervalSince1970;
        var msgType : UInt8 = 0
        data.copyBytes(to: &msgType, count: 4)
        if msgType == PacketTypes.HEARTBEAT {
            // Slime heartbeat
        } else if msgType == PacketTypes.RECEIVE_HEARTBEAT {
            // OwODriver heartbeat
        } else if msgType == PacketTypes.RECEIVE_VIBRATE {
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
        } else if msgType == PacketTypes.HANDSHAKE {
            //Leftover Handshake Message
        } else if msgType == PacketTypes.PING_PONG {
            sendUDP(data)
        } else if msgType == PacketTypes.CHANGE_MAG_STATUS {
            let restData = data.advanced(by: 4)
            let m = String(UInt32(bigEndian: restData.prefix(1).withUnsafeBytes { $0.load(as: UInt32.self) }))
            self.service.toggleMagnetometerUse(use: m == "y")
        } else {
            print("Unknown message type \(msgType)")
            print("Data \(String(data: data, encoding: .utf8))")
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
        provideFloats(floats: rot, len: 4, msgType: Int32(PacketTypes.ROTATION));
    }
    
    public func provideGyro(gyro: [Data]) {
        provideFloats(floats: gyro, len: 3, msgType: Int32(PacketTypes.GYRO));
    }
    
    public func provideAccel(accel: [Data]) {
        provideFloats(floats: accel, len: 3, msgType: Int32(PacketTypes.ACCEL));
    }
    
    public func provideMagnetometerUse(enabled: Bool) {
        if (!isConnected) {
            return;
        }
        
        let len = 12 + 2;
        var type = Int32(bigEndian: Int32(PacketTypes.SEND_MAG_STATUS))
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
    
    public func provideBatteryLevel() {
        
    }
    
    public func buttonPushed() {
        if (!isConnected) {
            return;
        }
        
        let len = 12 + 1;
        var type = Int32(bigEndian: Int32(PacketTypes.BUTTON_PUSHED))
        var id = Int64(bigEndian: packetId)
        
        var data = Data(capacity: len)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        
        sendUDP(data)
        packetId += 1;
        logger.addEntry("Button Pushed")
    }
    
    /*
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
    }*/
    
    func vibrate() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
}
