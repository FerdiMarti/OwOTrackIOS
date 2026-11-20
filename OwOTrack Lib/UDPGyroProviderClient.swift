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
    
    private var packetId: Int64 = 0     //only read or modified on sendQueue
    //SlimeVR drops every packet whose number isn't higher than the last one it received.
    //Sensor data arrives on several threads at once, so numbering and sending happen together on this serial queue.
    private let sendQueue = DispatchQueue(label: "UDPGyroProviderClient.send")
    //handshake retries, see handshake()
    private static let handshakeTries = 13
    private static let handshakeSlimeTries = 7
    private static let handshakeRetryInterval: TimeInterval = 0.25
    private let handshakeQueue = DispatchQueue(label: "UDPGyroProviderClient.handshake")
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
        sendQueue.sync { self.packetId = 0 }
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

        data.append(Data(bigEndian: Int32(PacketTypes.HANDSHAKE)))
        data.append(Data(bigEndian: Int64(0)))  //packet number

        if !slime {
            return data
        }

        let boardType: Int32 = 0
        let imuType: Int32 = 0
        let mcuType: Int32 = 0
        let imuInfo : [Int32] = [0, 0, 0]
        let firmwareBuild: Int32 = 8
        let firmware = "owoTrack8" // 9 bytes
        let firmwareData = Data(firmware.utf8)
        let firmwareLength : UInt8 = UInt8(firmware.count)
        let pseudoMac : [UInt8] = hardware.getPseudoMacAddress()
        data.append(Data(bigEndian: boardType))
        data.append(Data(bigEndian: imuType))
        data.append(Data(bigEndian: mcuType))
        for i in imuInfo {
            data.append(Data(bigEndian: i))
        }
        data.append(Data(bigEndian: firmwareBuild))
        data.append(firmwareLength)
        data.append(firmwareData)
        for i in pseudoMac {
            data.append(i)
        }
        data.append(UInt8(0xff))
        
        return data
    }
    
    //sends handshakes until the server replies, one try every 250 ms (all 13 tries take about 3 s, within TrackingService's 5 s wait)
    // if the user is running an old version of owoTrackVR driver,
    // recvfrom() will fail as the max packet length the old driver
    // supported was around 28 bytes. to maintain backwards
    // compatibility the slime extensions are not sent after 7
    // unanswered tries
    //the tries must be spaced out: sent all at once, the server answers several of them and also gets the
    //short legacy handshakes right after the real one
    func handshake() {
        isConnecting = true
        sendHandshake(attempt: 0)
    }

    private func sendHandshake(attempt: Int) {
        if isConnected || !isConnecting || attempt >= UDPGyroProviderClient.handshakeTries {
            return
        }
        let sendSlimeExtensions = attempt < UDPGyroProviderClient.handshakeSlimeTries
        self.connection?.sendUDP(buildHeaderInfo(slime: sendSlimeExtensions))
        handshakeQueue.asyncAfter(deadline: .now() + UDPGyroProviderClient.handshakeRetryInterval) {
            self.sendHandshake(attempt: attempt + 1)
        }
    }

    //the server's handshake reply is byte 3 followed by "Hey OVR =D <version>" in ASCII (SlimeVR pads it with zero bytes to 64 bytes)
    //returns the text after the first byte up to the first zero byte, or nil if the data doesn't start with byte 3
    private func handshakeReplyText(_ data: Data) -> String? {
        guard data.first == 3 else {
            return nil
        }
        return String(decoding: data.dropFirst().prefix { $0 != 0 }, as: UTF8.self)
    }

    //same checks as the owoTrack Android app, without crashing on short or unexpected replies
    func validateHandshakeResponse(data: Data) {
        guard let text = handshakeReplyText(data) else {
            //not a handshake reply, e.g. a heartbeat from a server that still knows this phone from an earlier connection.
            //ignore it, the next try follows anyway
            return
        }
        if (!text.hasPrefix("Hey OVR =D")) {
            handshakeFailed("The server did not respond correctly in the header. Ensure everything is up-to-date and that the port is correct.")
            return
        }
        let digits = text.dropFirst(11).prefix { $0 >= "0" && $0 <= "9" }   //"Hey OVR =D 5" -> "5"
        guard let version = Int(digits) else {
            handshakeFailed("The server did not send a valid version number. Please make sure everything is up to date.")
            return
        }
        if (version != UDPGyroProviderClient.CURRENT_VERSION) {
            handshakeFailed("Handshake failed, mismatching version"
                            + "\nServer version: \(version)"
                            + "\nClient version: \(UDPGyroProviderClient.CURRENT_VERSION)"
                            + "\nPlease make sure everything is up to date.")
            return
        }
        self.logger.addEntry("Handshake Succeded")
        self.successfulHandshake()
    }

    //the server answered but isn't compatible: log why and stop sending handshakes, TrackingService then reports the failed connection
    private func handshakeFailed(_ reason: String) {
        isConnecting = false
        logger.addEntry("Handshake Failed")
        logger.addEntry(reason)
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
        //replies to earlier handshake tries can still arrive after connecting. skip them:
        //read as a normal packet, their text looks like a huge message type and flips the byte order detection
        if handshakeReplyText(data)?.hasPrefix("Hey OVR =D") == true {
            return
        }
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
            //lets the server (owoTrack driver overlay) turn the magnetometer on or off, payload is a 2-byte char 'y' or 'n'
            if let c = readChar(data: restData) {
                self.service.toggleMagnetometerUse(use: c == "y")
            }
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
    
    //reads a 2-byte character (a Java char, as in the owoTrack protocol) depending on endian encoding
    //returns nil if the data is too short or not a valid character
    func readChar(data: Data) -> Character? {
        let bytes = [UInt8](data.prefix(2))
        if bytes.count < 2 {
            return nil
        }
        let value = receivingBigEndian
            ? UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            : UInt16(bytes[1]) << 8 | UInt16(bytes[0])
        guard let scalar = Unicode.Scalar(value) else {
            return nil
        }
        return Character(scalar)
    }
    
    //checks if connection timed out
    @objc func checkConnection() {
        if !isConnected {
            return
        }
        let time = Date().timeIntervalSince1970
        let timeDiff = time - lastHeartbeat
        if timeDiff > 10 {
            logger.addEntry("Connection with server lost")
            service.stop()
            return
        }
        return
    }
    
    //adds the header (message type + next packet number) and sends the packet
    //runs on sendQueue so packet numbers go out strictly increasing
    private func sendPacket(msgType: Int32, payload: Data) {
        sendQueue.async {
            var data = Data(capacity: 12 + payload.count)
            data.append(Data(bigEndian: msgType))
            data.append(Data(bigEndian: self.packetId))
            data.append(payload)
            self.connection?.sendUDP(data)
            self.packetId += 1
        }
    }

    private func provideFloats(floats: [Data], len: Int, msgType: Int32) {
        if (!isConnected) {
            return;
        }
        var payload = Data(capacity: len * 4)
        for elem in floats {
            payload.append(elem)
        }
        sendPacket(msgType: msgType, payload: payload)
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
    
    //sends whether the magnetometer is enabled, as a 2-byte big-endian char 'y' or 'n' like the owoTrack Android app
    //only used by the owoTrack driver, SlimeVR ignores it
    public func provideMagnetometerUse(enabled: Bool) {
        if (!isConnected) {
            return
        }

        let c = UInt16(UInt8(ascii: enabled ? "y" : "n"))
        sendPacket(msgType: Int32(PacketTypes.SEND_MAG_STATUS), payload: Data(bigEndian: c))
    }
    
    //sends current device battery level
    public func provideBatteryLevel(level: Float) {
        if (!isConnected) {
            return
        }
        
        sendPacket(msgType: Int32(PacketTypes.BATTERY_LEVEL), payload: Data(bigEndian: level))
    }
    
    //send that the volume button was pushed, not used by server afaik
    public func provideButtonPushed() {
        if (!isConnected) {
            return;
        }
        
        sendPacket(msgType: Int32(PacketTypes.BUTTON_PUSHED), payload: Data())
    }
}

extension Data {
    //the big-endian bytes of an integer, the byte order of every number the app sends to the server
    //copies the value's bytes safely; a buffer pointer made from &variable is only valid during that one call
    init<T: FixedWidthInteger>(bigEndian value: T) {
        self = Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    //the big-endian bytes of a float (its IEEE 754 bit pattern)
    init(bigEndian value: Float) {
        self.init(bigEndian: value.bitPattern)
    }
}
