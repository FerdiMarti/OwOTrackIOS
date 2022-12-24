//
//  UDPGyroProviderClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation

class PacketTypes {
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

//Uses one of the UDP clients to send the applications data to the server
class UDPGyroProviderClient {

    var connection: CompatibleUDPClient?
    var logger = Logger.getInstance()
    var hostUDP = "192.168.0.10"
    var portUDP = 6969
    
    private var packetId: Int64 = 0
    var isConnected: Bool = false
    var isConnecting: Bool = false //is true during handshake attempts
    var lastHeartbeat: Double = 0   //last message from server
    var service: TrackingService
    var connectionCheckTimer : Timer? //timer that regularly calls a method to check if connection is still valid
    var receivingBigEndian = true       //the app has to switch between handling data in BigEndian and LittleEndian because serer applications send data differently
    
    //switch between hardware classes depending on device type (iPhone or Apple Watch)
    #if os(iOS)
    let hardware = IPhoneHardware.self
    #elseif os(watchOS)
    let hardware = WatchHardware.self
    #endif
    
    public static var CURRENT_VERSION = 5
    
    init(host: String, port: String, service: TrackingService) {
        self.hostUDP = host
        self.portUDP = Int(port) ?? 6969
        self.service = service
    }
    
    func disconnectUDP() {
        logger.addEntry("Disconnecting Client")
        self.connection?.close()
        isConnected = false
        isConnecting = false
        connectionCheckTimer?.invalidate()
    }

    func connectToUDP() {
        //reset variables
        logger.reset()
        logger.addEntry("Attempting Connection")
        isConnected = false
        isConnecting = false
        packetId = 0
        lastHeartbeat = 0
        
        //Switch between UDPClient depending on OS version
        #if os(iOS)
        if #available(iOS 12.0, *) {
            self.connection = NWConnectionUDPClient(host: hostUDP, port: portUDP)
        } else {
            self.connection = SwiftSocketUDPClient(host: hostUDP, port: portUDP)
        }
        #elseif os(watchOS)
        if #available(watchOS 5.0, *) {
            self.connection = NWConnectionUDPClient(host: hostUDP, port: portUDP)
        } else {
            self.connection = SwiftSocketUDPClient(host: hostUDP, port: portUDP)
        }
        #endif
        
        self.connection?.open {
            self.logger.addEntry("Connection Ready")
            self.logger.addEntry("Attempting Handshake")
            self.runListener()
            self.handshake()
        }
    }
    
    //builds the data header either for legacy OwOTrack driver or SlimeVR server
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
        let imuInfo : [Int32] = [0, 0, 0]
        var firmwareBuild = Int32(bigEndian: 8)
        let firmware = "owoTrack8" // 9 bytes
        let firmwareData = Data(firmware.utf8)
        let firmwareLength : UInt8 = UInt8(firmware.count)
        let pseudoMac : [UInt8] = hardware.getPseudoMacAddress()
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
        isConnecting = true
        var tries = 0
        while(!isConnected && tries <= 12) {
            // if the user is running an old version of owoTrackVR driver,
            // recvfrom() will fail as the max packet length the old driver
            // supported was around 28 bytes. to maintain backwards
            // compatibility the slime extensions are not sent after a
            // certain number of failures
            let sendSlimeExtensions = (tries < 7)
            let sendData = buildHeaderInfo(slime: sendSlimeExtensions)
            self.connection?.sendUDP(sendData)
            tries += 1
        }
    }
    
    func validateHandshakeResponse(data: Data) {
        var result = String(data: data, encoding: .ascii)!
        if (!result.hasPrefix(String(Unicode.Scalar(3)))) {
            self.logger.addEntry("Handshake Failed")
            self.logger.addEntry("The server did not respond correctly. Ensure everything is up-to-date and that the port is correct.")
            return
        }
        result = String(result[result.index(result.startIndex, offsetBy: 1)...])
        if (!result.hasPrefix("Hey OVR =D")) {
            self.logger.addEntry("Handshake Failed")
            self.logger.addEntry("The server did not respond correctly in the header. Ensure everything is up-to-date and that the port is correct.")
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
            return
        }
        self.logger.addEntry("Handshake Succeded")
        self.successfulHandshake()
    }
    
    func successfulHandshake() {
        self.isConnected = true
        self.isConnecting = false
        self.lastHeartbeat = Date().timeIntervalSince1970
        //start timer to check connection regularly
        DispatchQueue.main.async {
            self.connectionCheckTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.checkConnection), userInfo: nil, repeats: true)
        }
    }
    
    //listen for incoming data, keep running while connected or while attempting handshake
    //Receive UDP runs in DispatchQueue
    func runListener() {
        self.connection?.receiveUDP(cb: { data in
            if data != nil {
                self.processReceivedData(data: data!, recursion: false)
            }
            if self.isConnected || self.isConnecting {
                self.runListener()
            }
        })
    }
    
    
    func processReceivedData(data: Data, recursion: Bool) {
        //if still connecting, the data could only be handshake
        if !isConnected && isConnecting {
            self.validateHandshakeResponse(data: data)
            return
        }
        
        self.lastHeartbeat = Date().timeIntervalSince1970;
        var msgType : UInt32 = 0
        msgType = readUInt32(data: data)
        var restData = data.advanced(by: 4)
        if msgType == PacketTypes.RECEIVE_HEARTBEAT {
            // Heartbeat
        } else if msgType == PacketTypes.RECEIVE_VIBRATE {
            // vibrate
            handleVibration(restData)
        } else if msgType == PacketTypes.HANDSHAKE{
            //additional handshake messages
        } else if msgType == PacketTypes.PING_PONG {
            //Ping, just send packet back
            self.connection?.sendUDP(data)
        } else if msgType == PacketTypes.CHANGE_MAG_STATUS {
            //let's the server switch the usage of the magnetometer, not used afaik
            let m = readString(data: restData, length: 1)
            self.service.toggleMagnetometerUse(use: m == "y")
        } else {
            // if message type is a very high number, it's probably because the encoding is wrong
            if (msgType >= 2048 && !recursion) {
                receivingBigEndian = !receivingBigEndian
                processReceivedData(data: data, recursion: true) //recusrion is neccessary to check in case the high packet type was not because of encoding
                return
            }
            print("Unknown message type \(msgType)")
            //print("Data \(String(data: data, encoding: .ascii))")
        }
    }
    
    func handleVibration(_ data: Data) {
        let duration = readFloat(data: data)
        var restData = data.advanced(by: 4)
        let frequency = readFloat(data: restData)
        restData = restData.advanced(by: 4)
        let amplitude = readFloat(data: restData)
        if #available(iOS 13.0, *) {
            if hardware.vibrateAdvanced(f: frequency, a: amplitude, d: duration) == false {
                hardware.vibrate()
            }
        } else {
            hardware.vibrate()
        }
    }
    
    //reads float depending on endian encoding
    func readFloat(data: Data) -> Float {
        if receivingBigEndian {
            return Float(bitPattern: UInt32(bigEndian: data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
        } else {
            return Float(bitPattern: UInt32(data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
        }
    }
    
    //reads UInt32 depending on endian encoding
    func readUInt32(data: Data) -> UInt32 {
        if receivingBigEndian {
            return UInt32(bigEndian: data.prefix(4).withUnsafeBytes{ $0.load(as: UInt32.self) })
        } else {
            return UInt32(data.prefix(4).withUnsafeBytes{ $0.load(as: UInt32.self) })
        }
    }
    
    //reads String depending on endian encoding
    func readString(data: Data, length: Int) -> String {
        var str = ""
        var restData = data
        while str.count < length {
            var char = ""
            if receivingBigEndian {
                char = String(UInt32(bigEndian: restData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
            } else {
                char = String(UInt32(restData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
            }
            str += char
            restData = data.advanced(by: 1)
        }
        return str
    }
    
    //checks if connection timed out
    @objc func checkConnection() {
        if !isConnected {
            return
        }
        let time = Date().timeIntervalSince1970
        let timeDiff = time - lastHeartbeat
        if timeDiff > 5 {
            logger.addEntry("Connection with server lost")
            service.stop()
            return
        }
        return
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

        self.connection?.sendUDP(data)
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
    
    //send if the magnetometer is enabled, not used by server afaik
    public func provideMagnetometerUse(enabled: Bool) {
        if (!isConnected) {
            return
        }
        
        let len = 12 + 2;
        var type = Int32(bigEndian: Int32(PacketTypes.SEND_MAG_STATUS))
        var id = Int64(bigEndian: packetId)
        let mstr = enabled ? "y" : "n"
        
        var data = Data(capacity: len)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        data.append(Data(mstr.utf8))
        
        self.connection?.sendUDP(data)
        packetId += 1
    }
    
    //sends current device battery level
    public func provideBatteryLevel(level: Float) {
        if (!isConnected) {
            return
        }
        
        let len = 12 + 4;
        var type = Int32(bigEndian: Int32(PacketTypes.BATTERY_LEVEL))
        var id = Int64(bigEndian: packetId)
        var bat = level.bitPattern.bigEndian
        var data = Data(capacity: len)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        data.append(UnsafeBufferPointer(start: &bat, count: 1))
        self.connection?.sendUDP(data)
        packetId += 1
    }
    
    //send that the volume button was pushed, not used by server afaik
    public func provideButtonPushed() {
        if (!isConnected) {
            return;
        }
        
        let len = 12 + 1;
        var type = Int32(bigEndian: Int32(PacketTypes.BUTTON_PUSHED))
        var id = Int64(bigEndian: packetId)
        
        var data = Data(capacity: len)
        data.append(UnsafeBufferPointer(start: &type, count: 1))
        data.append(UnsafeBufferPointer(start: &id, count: 1))
        
        self.connection?.sendUDP(data)
        packetId += 1;
    }
}
