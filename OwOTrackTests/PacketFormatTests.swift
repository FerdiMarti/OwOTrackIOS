//
//  PacketFormatTests.swift
//  OwOTrackTests
//
//  What the app sends, byte by byte, without a network: the client sends into a RecordingConnection.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Packet format")
    struct PacketFormat {

        @Test("SlimeVR handshake, read the way SlimeVR reads it")
        func slimeVRHandshake() throws {
            let (client, _, _) = connectedClient()
            let data = client.buildHeaderInfo(slime: true)
            let packet = try #require(SentPacket(data))
            #expect(packet.type == 3)
            #expect(packet.number == 0)
            let handshake = try #require(SlimeVRHandshake(packet: data))
            #expect(handshake.boardType == 13)      //SlimeVR's "owoTrack" board
            #expect(handshake.imuType == 0)
            #expect(handshake.mcuType == 5)         //SlimeVR's "owoTrack iOS" MCU
            #expect(handshake.protocolVersion == 9)
            #expect(handshake.mac == "02:0E:57:00:00:01")   //read after the firmware text, so its length is right too
        }

        @Test("the firmware text names the app version, but isn't a bare version number SlimeVR would compare with its releases")
        func firmwareText() throws {
            let (client, _, _) = connectedClient()
            let handshake = try #require(SlimeVRHandshake(packet: client.buildHeaderInfo(slime: true)))
            let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            #expect(handshake.firmware == "owoTrack iOS \(version)")
            #expect(handshake.firmware.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) == nil)
        }

        @Test("the handshake for the old driver fits its 28-byte limit")
        func oldDriverHandshake() throws {
            let (client, _, _) = connectedClient()
            let data = client.buildHeaderInfo(slime: false)
            #expect(data.count <= 28)
            #expect(try #require(SentPacket(data)).type == 3)
        }

        @Test("rotation goes as packet 1 to the old driver and as packet 17 once SlimeVR answered")
        func rotation() async throws {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            let quaternion = floats(0.1, 0.2, 0.3, 0.9)
            client.provideRot(rot: quaternion)
            #expect(await waitUntil { connection.packets.count == 1 })
            let old = try #require(connection.packets.first)
            #expect(old.type == 1)
            #expect(old.payload == quaternion.flatMap { [UInt8]($0) })

            await switchToSlimeVR(client, connection)
            client.provideRot(rot: quaternion)
            #expect(await waitUntil { connection.packets.count == 1 })
            let new = try #require(connection.packets.first)
            #expect(new.type == 17)
            //sensor 0, data type 1 (normal), x y z w, accuracy 0
            #expect(new.payload == [0, 1] + quaternion.flatMap { [UInt8]($0) } + [0])
        }

        @Test("the gyro only goes to the old driver")
        func gyro() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideGyro(gyro: floats(1, 2, 3))
            #expect(await waitUntil { connection.packets.map(\.type) == [2] })
            #expect(connection.packets.first?.payload == bytes(Float(1)) + bytes(Float(2)) + bytes(Float(3)))

            await switchToSlimeVR(client, connection)
            client.provideGyro(gyro: floats(1, 2, 3))
            await pause(0.2)
            #expect(connection.packets.isEmpty)
        }

        @Test("acceleration and battery level")
        func accelerationAndBattery() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideAccel(accel: floats(0, 0, -9.81))
            client.provideBatteryLevel(level: 0.42)
            #expect(await waitUntil { connection.packets.count == 2 })
            let packets = connection.packets
            #expect(packets.map(\.type) == [4, 12])
            #expect(packets.first?.payload == bytes(Float(0)) + bytes(Float(0)) + bytes(Float(-9.81)))
            #expect(packets.last?.payload == bytes(Float(0.42)))
        }

        @Test("the sensor description carries the magnetometer state", arguments: [
            (true, true, UInt8(0b11)), (true, false, UInt8(0b10)), (false, false, UInt8(0)),
        ])
        func sensorDescription(supported: Bool, enabled: Bool, bits: UInt8) async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideSensorInfo(magnetometerSupported: supported, magnetometerEnabled: enabled)
            #expect(await waitUntil { !connection.packets.isEmpty })
            let packet = connection.packets.first
            #expect(packet?.type == 15)
            #expect(packet?.payload == [0, 1, 0, 0, bits])     //sensor 0, status ok, IMU unknown, 2 bytes of settings
        }

        @Test("the sensor description is repeated until SlimeVR acknowledges it")
        func sensorDescriptionRepeats() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideSensorInfo(magnetometerSupported: true, magnetometerEnabled: true)
            #expect(await waitUntil(2.5) { connection.packets.filter { $0.type == 15 }.count >= 2 })
            await switchToSlimeVR(client, connection)
            await pause(1.3)
            #expect(!connection.packets.contains { $0.type == 15 })
        }

        @Test("volume buttons: resets for SlimeVR, the button packet for the old driver")
        func volumeButtons() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideButtonPushed(volumeUp: true)
            client.provideButtonPushed(volumeUp: false)
            #expect(await waitUntil { connection.packets.count == 2 })
            #expect(connection.packets.map(\.type) == [60, 60])
            #expect(connection.packets.allSatisfy { $0.payload.isEmpty })

            await switchToSlimeVR(client, connection)
            client.provideButtonPushed(volumeUp: true)
            client.provideButtonPushed(volumeUp: false)
            #expect(await waitUntil { connection.packets.count == 2 })
            #expect(connection.packets.map(\.type) == [21, 21])
            #expect(connection.packets.map(\.payload) == [[3], [2]])     //yaw reset, full reset
        }

        @Test("volume up and down are told apart from the old and new volume")
        func volumeDirection() async {
            let (client, connection, service) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            await switchToSlimeVR(client, connection)
            let changes: [[NSKeyValueChangeKey: Any]] = [
                [.oldKey: NSNumber(value: 0.5), .newKey: NSNumber(value: 0.5625)],
                [.oldKey: NSNumber(value: 0.5), .newKey: NSNumber(value: 0.4375)],
                [:],    //no values: counts as volume up
            ]
            for change in changes {
                service.observeValue(forKeyPath: "outputVolume", of: nil, change: change, context: nil)
            }
            #expect(await waitUntil { connection.packets.count == 3 })
            #expect(connection.packets.map(\.payload) == [[3], [2], [3]])
        }

        @Test("the magnetometer state for the old driver is a 2-byte char")
        func magnetometerState() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.provideMagnetometerUse(enabled: true)
            client.provideMagnetometerUse(enabled: false)
            #expect(await waitUntil { connection.packets.count == 2 })
            #expect(connection.packets.map(\.type) == [61, 61])
            #expect(connection.packets.map(\.payload) == [[0, UInt8(ascii: "y")], [0, UInt8(ascii: "n")]])
        }

        @Test("nothing is sent while not connected")
        func notConnected() async {
            let (client, connection, _) = connectedClient()
            client.isConnected = false
            client.provideRot(rot: floats(0, 0, 0, 1))
            client.provideAccel(accel: floats(0, 0, 1))
            client.provideBatteryLevel(level: 1)
            client.provideButtonPushed(volumeUp: true)
            await pause(0.2)
            #expect(connection.sent.isEmpty)
        }

        @Test("packet numbers keep increasing while several sensor threads send")
        func packetNumbers() async {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            DispatchQueue.concurrentPerform(iterations: 4) { thread in
                for _ in 0..<250 {
                    if thread % 2 == 0 {
                        client.provideRot(rot: floats(0, 0, 0, 1))
                    } else {
                        client.provideAccel(accel: floats(0, 0, 1))
                    }
                }
            }
            #expect(await waitUntil { connection.packets.count == 1000 })
            let numbers = connection.packets.map(\.number)
            #expect(numbers == Array(0..<1000))     //SlimeVR drops a packet whose number isn't higher than the last (0 is always accepted)
        }

        @Test("numbers are sent big-endian")
        func bigEndian() {
            #expect([UInt8](Data(bigEndian: UInt32(0x0102_0304))) == [1, 2, 3, 4])
            #expect([UInt8](Data(bigEndian: Int64(1))) == [0, 0, 0, 0, 0, 0, 0, 1])
            #expect([UInt8](Data(bigEndian: Float(1))) == [0x3F, 0x80, 0, 0])
        }
    }
}
