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
    static let SENSOR_INFO = 15;            //SlimeVR: sensor description, and SlimeVR's acknowledgement of it
    static let ROTATION_DATA = 17;          //SlimeVR: replaces ROTATION, which SlimeVR marks as deprecated
    static let USER_ACTION = 21;            //SlimeVR: asks the server for a reset, see the USER_ACTION_ ids
    static let ACK_CONFIG_CHANGE = 24;      //SlimeVR: confirms a SET_CONFIG_FLAG
    static let SET_CONFIG_FLAG = 25;        //SlimeVR: changes a sensor setting
    static let BUTTON_PUSHED = 60;
    static let SEND_MAG_STATUS = 61;
    static let CHANGE_MAG_STATUS = 62;
    static let RECEIVE_HEARTBEAT = 1;
    static let RECEIVE_VIBRATE = 2;
    static let CONFIG_MAG_ENABLED = 1;      //SET_CONFIG_FLAG setting id of the magnetometer
    static let USER_ACTION_RESET_FULL = 2;
    static let USER_ACTION_RESET_YAW = 3;
}

//Uses one of the UDP clients to send the applications data to the server
class UDPGyroProviderClient: MotionSink {

    var connection: CompatibleUDPClient?
    let logger: Logger
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
    //pause before listening again after a failed receive: a broken connection fails instantly, retrying right away spun at full CPU
    private static let receiveRetryDelay: TimeInterval = 0.1
    var lastProblem: String?    //last connection problem that was logged, to log each reason only once. Handed on between reconnect attempts
    var quiet = false           //reconnect attempts: don't log the routine steps (connecting, handshake) on every attempt
    //SlimeVR (protocol 9+) only accepts data after the app described its sensor. Only SlimeVR acknowledges that description,
    //so the acknowledgement also tells the app it talks to SlimeVR and not the old owoTrack driver. All of these are only used on sendQueue
    private var isSlimeVR = false
    private var magnetometerSupported = false
    private var magnetometerEnabled = false
    private var sensorInfoPending = false       //description sent but not acknowledged yet
    private var sensorInfoTries = 0
    private var sensorInfoRound = 0             //a new description stops the resends of the previous one
    private static let sensorInfoRetryInterval: TimeInterval = 1
    private static let sensorInfoMaxTries = 30  //the old owoTrack driver never acknowledges, so stop after that
    //written by the network thread, read by the main thread, the sensor threads and TrackingService's connect loop, so guarded by a lock
    private let stateLock = NSLock()
    private var _isConnected = false
    private var _isConnecting = false
    private var _lastHeartbeat: Double = 0
    var isConnected: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isConnected }
        set { stateLock.lock(); _isConnected = newValue; stateLock.unlock() }
    }
    var isConnecting: Bool {   //is true during handshake attempts
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isConnecting }
        set { stateLock.lock(); _isConnecting = newValue; stateLock.unlock() }
    }
    var lastHeartbeat: Double {   //last message from server
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastHeartbeat }
        set { stateLock.lock(); _lastHeartbeat = newValue; stateLock.unlock() }
    }
    //the short handshake of the old protocol went out: a reply after that comes from the old owoTrack driver,
    //which can't read SlimeVR's longer handshake (SlimeVR answers the first one right away)
    private var _shortHandshakeSent = false
    private var shortHandshakeSent: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _shortHandshakeSent }
        set { stateLock.lock(); _shortHandshakeSent = newValue; stateLock.unlock() }
    }
    //weak: the service keeps its client, so a strong reference here kept both alive after the session (the relayed watch's leaked)
    weak var service: TrackingService?
    private let localPortKey: String
    private let firmwarePlatform: String
    private let heartbeatTimeout: TimeInterval
    var connectionCheckTimer : Timer? //timer that regularly calls a method to check if connection is still valid
    var receivingBigEndian = true       //the app has to switch between handling data in BigEndian and LittleEndian because serer applications send data differently
    
    //the device's hardware, from TrackingService (a fake in the tests)
    let hardware: TrackerHardware
    
    public static var CURRENT_VERSION = 5
    
    init(host: String, port: String, service: TrackingService) {
        self.hostUDP = host
        self.portUDP = Int(port) ?? 6969
        self.service = service
        logger = service.logger
        hardware = service.hardware
        localPortKey = service.localPortKey
        firmwarePlatform = service.firmwarePlatform
        heartbeatTimeout = service.timing.heartbeatTimeout
    }
    
    //logIt is false when the user didn't ask for it: a lost connection or a failed reconnect attempt
    func disconnectUDP(logIt: Bool = true) {
        if logIt {
            logStep("Disconnecting Client")
        }
        //clear the flags before closing, so the listener knows the connection was closed on purpose
        isConnected = false
        isConnecting = false
        self.connection?.close()
        //the timer runs on the main thread and must be invalidated there
        DispatchQueue.main.async {
            self.connectionCheckTimer?.invalidate()
        }
    }

    func connectToUDP() {
        //reset variables
        if !quiet {
            logger.reset()
        }
        logStep("Attempting Connection")
        isConnected = false
        isConnecting = false
        sendQueue.sync { self.packetId = 0 }
        lastHeartbeat = 0

        self.connection = NWConnectionUDPClient(host: hostUDP, port: portUDP, portKey: localPortKey)

        self.connection?.open(cb: {
            self.logStep("Connection Ready")
            self.logStep("Attempting Handshake")
            self.runListener()
            self.handshake()
        }, onProblem: { problem in
            self.connectionProblem(problem)
        })
    }

    //routine connection steps, not logged on reconnect attempts
    private func logStep(_ entry: String) {
        if !quiet {
            logger.addEntry(entry)
        }
    }

    //logs why connecting doesn't work, but not the same reason twice in a row
    private func logProblem(_ reason: String) {
        if reason != lastProblem {
            lastProblem = reason
            logger.addEntry(reason)
        }
    }

    //the network layer reported why the connection can't be used. log the reason, so the user sees it and not only a timeout.
    //a fatal problem won't recover: stop the handshake, and if connected, report the lost connection now instead of after the heartbeat timeout
    func connectionProblem(_ problem: ConnectionProblem) {
        logProblem(problem.reason)
        if problem.localNetworkDenied {
            service?.connectUI?.setLocalNetworkAccess(.denied)
        }
        if !problem.fatal {
            return
        }
        isConnecting = false    //stops the handshake tries, TrackingService then reports the failed connection
        if isConnected {
            logger.addEntry("Connection with server lost")
            DispatchQueue.main.async {
                self.service?.connectionLost(client: self)     //on the main thread like the heartbeat timeout
            }
        }
    }
    
    //builds the data header either for legacy OwOTrack driver or SlimeVR server
    func buildHeaderInfo(slime: Bool) -> Data {
        return UDPGyroProviderClient.handshakePacket(slime: slime, mac: hardware.getPseudoMacAddress(), platform: firmwarePlatform)
    }

    //the handshake, also sent when searching the network for the server (LocalServerFinder)
    static func handshakePacket(slime: Bool, mac pseudoMac: [UInt8], platform: String) -> Data {
        var len = 12
        if slime { len += 36 + 9 }
        
        var data = Data(capacity: len)

        data.append(Data(bigEndian: Int32(PacketTypes.HANDSHAKE)))
        data.append(Data(bigEndian: Int64(0)))  //packet number

        if !slime {
            return data
        }

        //SlimeVR's ids for this app, shown in its tracker settings: board "owoTrack" (13) and MCU "owoTrack iOS" (5).
        //SlimeVR has no id for watchOS; the firmware text tells the two apart (also for the watch the iPhone relays)
        let boardType: Int32 = 13
        let imuType: Int32 = 0
        let mcuType: Int32 = 5
        let imuInfo : [Int32] = [0, 0, 0]
        let firmwareBuild: Int32 = 9  //SlimeVR protocol version: since 9, the sensor is described by a SENSOR_INFO packet
        //shown as the tracker's firmware version in SlimeVR, e.g. "owoTrack iOS 1.12".
        //not a bare version number like "1.12.0": SlimeVR compares those with its own firmware releases
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let firmware = "owoTrack \(platform) \(appVersion)"
        let firmwareData = Data(firmware.utf8)
        let firmwareLength : UInt8 = UInt8(firmwareData.count)
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
        if !sendSlimeExtensions {
            shortHandshakeSent = true
        }
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
        self.logStep("Handshake Succeeded")
        self.successfulHandshake()
    }

    //the server answered but isn't compatible: log why and stop sending handshakes, TrackingService then reports the failed connection
    private func handshakeFailed(_ reason: String) {
        isConnecting = false
        logStep("Handshake Failed")
        logProblem(reason)
    }
    
    func successfulHandshake() {
        self.isConnected = true
        self.isConnecting = false
        self.lastHeartbeat = Date().timeIntervalSince1970
        if shortHandshakeSent {
            service?.serverDetected(.owoTrackDriver, by: self)
        }
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
            if !(self.isConnected || self.isConnecting) {
                return
            }
            if data != nil {
                self.runListener()
            } else {
                //receiving failed: wait a moment before listening again (a failed connection is reported and closed separately)
                DispatchQueue.global().asyncAfter(deadline: .now() + UDPGyroProviderClient.receiveRetryDelay) {
                    if self.isConnected || self.isConnecting {
                        self.runListener()
                    }
                }
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
        //every packet starts with a 4-byte message type, anything shorter is broken
        if data.count < 4 {
            return
        }
        var msgType : UInt32 = 0
        msgType = readUInt32(data: data)
        let restData = data.advanced(by: 4)
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
                self.service?.toggleMagnetometerUse(use: c == "y", by: self)
            }
        } else if msgType == PacketTypes.SENSOR_INFO {
            //SlimeVR acknowledges the sensor description
            sensorInfoAcknowledged()
        } else if msgType == PacketTypes.SET_CONFIG_FLAG {
            handleSetConfigFlag(restData)
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
    
    //SlimeVR changes a sensor setting: 8-byte packet number, sensor id, 2-byte setting id, new state (big-endian).
    //the magnetometer is the only setting this app has. Every change is confirmed, like SlimeVR's own trackers do
    func handleSetConfigFlag(_ data: Data) {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count < 12 {
            return
        }
        let sensorId = bytes[8]
        let setting = UInt16(bytes[9]) << 8 | UInt16(bytes[10])
        let enabled = bytes[11] != 0
        if setting == PacketTypes.CONFIG_MAG_ENABLED && (sensorId == 0 || sensorId == 255) {   //255 means all sensors
            service?.toggleMagnetometerUse(use: enabled, by: self)
        }
        var payload = Data([sensorId])
        payload.append(Data(bigEndian: setting))
        sendPacket(msgType: Int32(PacketTypes.ACK_CONFIG_CHANGE), payload: payload)
    }

    func handleVibration(_ data: Data) {
        //three floats: duration, frequency, amplitude
        if data.count < 12 {
            return
        }
        let duration = readFloat(data: data)
        var restData = data.advanced(by: 4)
        let frequency = readFloat(data: restData)
        restData = restData.advanced(by: 4)
        let amplitude = readFloat(data: restData)
        if hardware.vibrateAdvanced(f: frequency, a: amplitude, d: duration) == false {
            hardware.vibrate()
        }
    }
    
    //reads float depending on endian encoding
    func readFloat(data: Data) -> Float {
        return Float(bitPattern: readUInt32(data: data))
    }

    //reads UInt32 from the first 4 bytes depending on endian encoding, 0 if there are fewer.
    //built byte by byte: loading a UInt32 straight from the buffer needs 4-byte aligned memory,
    //which received data doesn't guarantee (debug builds stopped with a misaligned load)
    func readUInt32(data: Data) -> UInt32 {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count < 4 {
            return 0
        }
        let bigEndianValue = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return receivingBigEndian ? bigEndianValue : bigEndianValue.byteSwapped
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
        if timeDiff > heartbeatTimeout {
            logger.addEntry("Connection with server lost")
            service?.connectionLost(client: self)
            return
        }
        return
    }
    
    //adds the header (message type + next packet number) and sends the packet
    //runs on sendQueue so packet numbers go out strictly increasing
    private func sendPacket(msgType: Int32, payload: Data) {
        sendQueue.async {
            self.sendNow(msgType: msgType, payload: payload)
        }
    }

    //only call on sendQueue
    private func sendNow(msgType: Int32, payload: Data) {
        var data = Data(capacity: 12 + payload.count)
        data.append(Data(bigEndian: msgType))
        data.append(Data(bigEndian: self.packetId))
        data.append(payload)
        self.connection?.sendUDP(data)
        self.packetId += 1
    }

    //SlimeVR: describes the sensor and its magnetometer, resent every second until SlimeVR acknowledges it
    public func provideSensorInfo(magnetometerSupported: Bool, magnetometerEnabled: Bool) {
        sendQueue.async {
            self.magnetometerSupported = magnetometerSupported
            self.magnetometerEnabled = magnetometerEnabled
            self.startSensorInfo()
        }
    }

    //the magnetometer was switched while connected. SlimeVR gets a new description; the owoTrack driver doesn't need one
    public func sensorConfigChanged(magnetometerEnabled: Bool) {
        sendQueue.async {
            self.magnetometerEnabled = magnetometerEnabled
            if self.isSlimeVR {
                self.startSensorInfo()
            }
        }
    }

    //only call on sendQueue
    private func startSensorInfo() {
        sensorInfoPending = true
        sensorInfoTries = 0
        sensorInfoRound += 1
        sendSensorInfo(round: sensorInfoRound)
    }

    //only call on sendQueue
    private func sendSensorInfo(round: Int) {
        if !isConnected || !sensorInfoPending || round != sensorInfoRound || sensorInfoTries >= UDPGyroProviderClient.sensorInfoMaxTries {
            return
        }
        sensorInfoTries += 1
        //sensor 0, status 1 (ok), IMU type 0 (unknown), then 2 bytes of settings: bit 1 = magnetometer supported, bit 0 = enabled
        let config: UInt16 = magnetometerSupported ? (magnetometerEnabled ? 0b11 : 0b10) : 0
        var payload = Data([0, 1, 0])
        payload.append(Data(bigEndian: config))
        sendNow(msgType: Int32(PacketTypes.SENSOR_INFO), payload: payload)
        sendQueue.asyncAfter(deadline: .now() + UDPGyroProviderClient.sensorInfoRetryInterval) {
            self.sendSensorInfo(round: round)
        }
    }

    private func sensorInfoAcknowledged() {
        sendQueue.async {
            self.sensorInfoPending = false
            if !self.isSlimeVR {
                self.isSlimeVR = true
                self.logger.addEntry("SlimeVR server detected")
                self.service?.serverDetected(.slimeVR, by: self)
            }
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
        if (!isConnected) {
            return
        }
        var floats = Data(capacity: 16)
        for elem in rot {
            floats.append(elem)
        }
        sendQueue.async {
            if self.isSlimeVR {
                //rotation data: sensor 0, data type 1 (normal), x y z w, accuracy 0 (unknown)
                var payload = Data([0, 1])
                payload.append(floats)
                payload.append(0)
                self.sendNow(msgType: Int32(PacketTypes.ROTATION_DATA), payload: payload)
            } else {
                self.sendNow(msgType: Int32(PacketTypes.ROTATION), payload: floats)
            }
        }
    }

    public func provideGyro(gyro: [Data]) {
        if (!isConnected) {
            return
        }
        var floats = Data(capacity: 12)
        for elem in gyro {
            floats.append(elem)
        }
        sendQueue.async {
            if self.isSlimeVR {
                return  //SlimeVR doesn't use gyro packets
            }
            self.sendNow(msgType: Int32(PacketTypes.GYRO), payload: floats)
        }
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
    
    //a volume button press. SlimeVR ignores the owoTrack button packet, so it gets a reset instead:
    //volume up asks for a yaw reset, volume down for a full reset (SlimeVR applies its reset delays).
    //the owoTrack driver gets the button packet as before
    public func provideButtonPushed(volumeUp: Bool) {
        if (!isConnected) {
            return;
        }

        sendQueue.async {
            if self.isSlimeVR {
                let action = volumeUp ? PacketTypes.USER_ACTION_RESET_YAW : PacketTypes.USER_ACTION_RESET_FULL
                self.sendNow(msgType: Int32(PacketTypes.USER_ACTION), payload: Data([UInt8(action)]))
                self.logger.addEntry(volumeUp ? "Yaw reset sent to SlimeVR" : "Full reset sent to SlimeVR")
            } else {
                self.sendNow(msgType: Int32(PacketTypes.BUTTON_PUSHED), payload: Data())
                self.logger.addEntry("Button Pushed")
            }
        }
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
