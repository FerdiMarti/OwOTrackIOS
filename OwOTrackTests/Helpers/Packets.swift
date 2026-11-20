//
//  Packets.swift
//  OwOTrackTests
//

import Foundation
@testable import OwOTrack_iOS

//a packet the app sent: 4-byte message type, 8-byte packet number, payload (all big-endian)
struct SentPacket {
    let type: UInt32
    let number: Int64
    let payload: [UInt8]
    let size: Int

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        if bytes.count < 12 {
            return nil
        }
        type = UInt32(bigEndianBytes: bytes[0..<4])
        number = Int64(bitPattern: UInt64(bigEndianBytes: bytes[4..<12]))
        payload = Array(bytes[12...])
        size = bytes.count
    }
}

//the handshake as SlimeVR v21.1.0 reads it: a port of UDPPacket3Handshake.readData, the remaining-bytes checks included
struct SlimeVRHandshake {
    var boardType: Int32 = 0
    var imuType: Int32 = 0
    var mcuType: Int32 = 0
    var protocolVersion: Int32 = 0
    var firmware = ""
    var mac: String?

    init?(packet data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, UInt32(bigEndianBytes: bytes[0..<4]) == 3 else {
            return nil
        }
        var position = 12
        func remaining() -> Int { bytes.count - position }
        func readInt() -> Int32 {
            defer { position += 4 }
            return Int32(bitPattern: UInt32(bigEndianBytes: bytes[position..<position + 4]))
        }
        if remaining() == 0 { return }
        if remaining() > 3 { boardType = readInt() }
        if remaining() > 3 { imuType = readInt() }
        if remaining() > 3 { mcuType = readInt() }
        if remaining() > 11 { position += 12 }     //IMU info
        if remaining() > 3 { protocolVersion = readInt() }
        var length = 0
        if remaining() > 0 {
            length = Int(bytes[position])
            position += 1
        }
        while length > 0 {      //stops at a zero byte like SlimeVR
            let c = bytes[position]
            position += 1
            length -= 1
            if c == 0 { break }
            firmware.append(Character(Unicode.Scalar(c)))
        }
        if remaining() >= 6 {
            mac = bytes[position..<position + 6].map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }
}

extension FixedWidthInteger {
    init(bigEndianBytes bytes: ArraySlice<UInt8>) {
        self = bytes.reduce(0) { $0 << 8 | Self($1) }
    }
}

//the bytes of a big-endian number
func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    return [UInt8](Data(bigEndian: value))
}

func bytes(_ value: Float) -> [UInt8] {
    return [UInt8](Data(bigEndian: value))
}

//floats the way GyroHandler hands them to the client
func floats(_ values: Float...) -> [Data] {
    return values.map { Data(bigEndian: $0) }
}

//a packet as SlimeVR sends it: type, packet number, payload
func slimeVRPacket(type: UInt32, number: Int64 = 1, payload: [UInt8] = []) -> Data {
    return Data(bytes(type) + bytes(number) + payload)
}

//a packet as the old owoTrack driver sends it: type and payload, no packet number
func driverPacket(type: UInt32, payload: [UInt8] = []) -> Data {
    return Data(bytes(type) + payload)
}

//handshake replies: the old driver's, and SlimeVR's (the same text, padded with zero bytes to 64 bytes)
let driverHandshakeReply: [UInt8] = [3] + Array("Hey OVR =D 5".utf8)
let slimeVRHandshakeReply: [UInt8] = driverHandshakeReply + [UInt8](repeating: 0, count: 64 - driverHandshakeReply.count)

//polls a condition without blocking the main thread, where the app's timers run. True if it became true in time
func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

func pause(_ seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

//the connection log the app shows
var appLog: String {
    return Logger.getInstance().get()
}
