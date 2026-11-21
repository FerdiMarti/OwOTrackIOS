//
//  ServerDataTests.swift
//  OwOTrackTests
//
//  What the app does with data from the server, including broken data, without a network.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Reading server data")
    struct ServerData {

        //a client waiting for the handshake reply
        func handshakingClient() -> (client: UDPGyroProviderClient, connection: RecordingConnection) {
            let (client, connection, _) = connectedClient()
            client.isConnected = false
            client.isConnecting = true
            return (client, connection)
        }

        @Test("the handshake replies of the old driver and of SlimeVR are accepted", arguments: [driverHandshakeReply, slimeVRHandshakeReply])
        func validHandshakeReply(reply: [UInt8]) {
            let (client, _) = handshakingClient()
            defer { client.disconnectUDP(logIt: false) }
            client.processReceivedData(data: Data(reply), recursion: false)
            #expect(client.isConnected)
            #expect(!client.isConnecting)
        }

        @Test("unusable handshake replies don't crash and don't connect", arguments: [
            [], [3], [3, 0x48], [7, 1, 2], Array("Hey OVR =D 5".utf8), [3] + Array("Hey OVR =D".utf8),
        ])
        func unusableHandshakeReply(reply: [UInt8]) {
            let (client, _) = handshakingClient()
            defer { client.disconnectUDP(logIt: false) }
            client.processReceivedData(data: Data(reply), recursion: false)
            #expect(!client.isConnected)
        }

        @Test("a wrong reply text stops the handshake and says why")
        func wrongReplyText() {
            let (client, _) = handshakingClient()
            Logger.getInstance().reset()
            client.processReceivedData(data: Data([3] + Array("Hello".utf8)), recursion: false)
            #expect(!client.isConnected)
            #expect(!client.isConnecting)
            #expect(appLog.contains("did not respond correctly"))
        }

        @Test("another protocol version stops the handshake and says why")
        func otherVersion() {
            let (client, _) = handshakingClient()
            Logger.getInstance().reset()
            client.processReceivedData(data: Data([3] + Array("Hey OVR =D 4".utf8)), recursion: false)
            #expect(!client.isConnected)
            #expect(!client.isConnecting)
            #expect(appLog.contains("mismatching version"))
        }

        @Test("short and misaligned data is read safely")
        func shortAndMisaligned() {
            let (client, _, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            let data = Data([0xFF, 0x00, 0x00, 0x00, 0x02])
            #expect(client.readUInt32(data: data.advanced(by: 1)) == 2)    //starts at an odd address
            #expect(client.readUInt32(data: Data([1, 2, 3])) == 0)
            #expect(client.readChar(data: Data([0])) == nil)
            for length in 0..<4 {
                client.processReceivedData(data: Data(repeating: 1, count: length), recursion: false)
            }
        }

        @Test("the byte order is detected from the message type")
        func byteOrder() {
            let (client, _, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            #expect(client.receivingBigEndian)
            client.processReceivedData(data: Data([1, 0, 0, 0]), recursion: false)    //a little-endian heartbeat
            #expect(!client.receivingBigEndian)
        }

        @Test("handshake replies arriving after connecting don't change the byte order")
        func lateHandshakeReply() {
            let (client, _, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.processReceivedData(data: Data(slimeVRHandshakeReply), recursion: false)
            #expect(client.receivingBigEndian)
        }

        @Test("messages from the server keep the connection alive")
        func heartbeat() {
            let (client, _, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.lastHeartbeat = 0
            client.processReceivedData(data: slimeVRPacket(type: 1), recursion: false)
            #expect(Date().timeIntervalSince1970 - client.lastHeartbeat < 1)
        }

        @Test("SlimeVR switches the magnetometer and gets a confirmation", arguments: [
            (UInt8(0), UInt16(1), true),        //sensor 0, magnetometer: switched
            (UInt8(255), UInt16(1), true),      //all sensors: switched
            (UInt8(3), UInt16(1), false),       //another sensor: only confirmed
            (UInt8(0), UInt16(2), false),       //another setting: only confirmed
        ])
        func setConfigFlag(sensor: UInt8, setting: UInt16, switches: Bool) async {
            let (client, connection, service) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            let ui = RecordingUI()
            service.connectUI = ui
            service.magnetometer = true
            client.processReceivedData(data: slimeVRPacket(type: 25, number: 7, payload: [sensor] + bytes(setting) + [0]), recursion: false)
            #expect(await waitUntil { service.magnetometer == !switches })     //switched on the main thread
            #expect(ui.magnetometerToggles == (switches ? [false] : []))
            #expect(await waitUntil { connection.packets.contains { $0.type == 24 } })
            #expect(connection.packets.first { $0.type == 24 }?.payload == [sensor] + bytes(setting))
        }

        @Test("the old driver's overlay switches the magnetometer")
        func driverMagnetometerSwitch() async {
            let (client, _, service) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            client.processReceivedData(data: driverPacket(type: 62, payload: [0, UInt8(ascii: "n")]), recursion: false)
            #expect(await waitUntil { service.magnetometer == false })     //switched on the main thread
            client.processReceivedData(data: driverPacket(type: 62, payload: [0, UInt8(ascii: "y")]), recursion: false)
            #expect(await waitUntil { service.magnetometer == true })
            client.processReceivedData(data: driverPacket(type: 62, payload: [0]), recursion: false)    //too short: ignored
            await pause(0.1)
            #expect(service.magnetometer == true)
        }

        @Test("a handshake reply after the attempt was given up doesn't bring the connection back")
        func lateHandshakeReply() async {
            let (client, _, service) = connectedClient()
            client.disconnectUDP(logIt: false)      //TrackingService gave up on this attempt at its time limit
            client.successfulHandshake()            //and the reply arrives right after
            #expect(!client.isConnected)
            await pause(0.2)
            #expect(client.connectionCheckTimer?.isValid != true)      //no leftover check reporting a lost connection every second
            _ = service
        }

        @Test("vibration requests reach the hardware, short ones are ignored")
        func vibration() {
            let (client, _, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            //duration, frequency, amplitude
            client.processReceivedData(data: driverPacket(type: 2, payload: bytes(Float(0.5)) + bytes(Float(0.25)) + bytes(Float(0.75))), recursion: false)
            #expect(FakeHardware.events == ["vibrate f=0.25 a=0.75 d=0.5"])
            client.processReceivedData(data: driverPacket(type: 2, payload: bytes(Float(0.5))), recursion: false)
            #expect(FakeHardware.events.count == 1)
        }

        @Test("a blocked local network is reported to the screen and logged")
        func localNetworkDenied() {
            let (client, _, service) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            let ui = RecordingUI()
            service.connectUI = ui
            Logger.getInstance().reset()
            client.connectionProblem(ConnectionProblem(reason: "Local network access is denied", fatal: false, localNetworkDenied: true))
            #expect(ui.localNetwork == [.denied])
            #expect(appLog.contains("Local network access is denied"))
            client.connectionProblem(ConnectionProblem(reason: "Can't reach the server", fatal: false))
            #expect(ui.localNetwork == [.denied])   //other problems don't change it
        }

        @Test("a ping is answered with the same packet")
        func ping() {
            let (client, connection, _) = connectedClient()
            defer { client.disconnectUDP(logIt: false) }
            let ping = slimeVRPacket(type: 10, number: 3, payload: [1, 2, 3, 4])
            client.processReceivedData(data: ping, recursion: false)
            #expect(connection.sent == [ping])
        }
    }
}
