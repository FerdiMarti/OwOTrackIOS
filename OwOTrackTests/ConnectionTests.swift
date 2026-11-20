//
//  ConnectionTests.swift
//  OwOTrackTests
//
//  Connecting to a fake SlimeVR server on 127.0.0.1, through the real network code.
//

import Foundation
import Network
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Connection", .timeLimit(.minutes(1)))
    struct Connection {

        @Test("connects to SlimeVR, describes the sensor and then sends SlimeVR's packets")
        func connectsToSlimeVR() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                let handshake = try #require(server.lastHandshake)
                #expect(handshake.boardType == 13)
                #expect(handshake.mcuType == 5)
                #expect(handshake.protocolVersion == 9)
                #expect(handshake.mac == "02:0E:57:00:00:01")
                #expect(await waitUntil { appLog.contains("SlimeVR server detected") })
                #expect(await waitUntil { ui.serverTypes == [.slimeVR] })
                #expect(ui.localNetwork == [.granted])

                let detected = Date()
                try #require(service.client).provideRot(rot: floats(0, 0, 0, 1))
                #expect(await waitUntil { !server.received(type: 17, after: detected).isEmpty })
                #expect(server.received(type: 1, after: detected).isEmpty)
                //while connected: no auto-lock, background running, volume buttons
                #expect(FakeHardware.events.starts(with: ["auto-lock prevented", "volume buttons on", "background started"]))
            }
            #expect(FakeHardware.events.suffix(3) == ["auto-lock allowed", "volume buttons off", "background stopped"])
        }

        @Test("SlimeVR switches the magnetometer: the switch follows, SlimeVR gets a confirmation and a new description")
        func slimeVRSwitchesMagnetometer() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil { appLog.contains("SlimeVR server detected") })
                let before = Date()
                server.send(type: 25, payload: [0, 0, 1, 0])    //sensor 0, magnetometer, off
                #expect(await waitUntil { service.magnetometer == false })
                #expect(ui.magnetometerToggles == [false])
                #expect(await waitUntil { server.received(type: 24, after: before).first?.packet.payload == [0, 0, 1] })
                #expect(await waitUntil { !server.received(type: 15, after: before).isEmpty })
            }
        }

        @Test("volume buttons send resets to SlimeVR")
        func volumeButtonResets() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, _ in
                #expect(await waitUntil { appLog.contains("SlimeVR server detected") })
                service.observeValue(forKeyPath: "outputVolume", of: nil, change: [.oldKey: NSNumber(value: 0.5), .newKey: NSNumber(value: 0.5625)], context: nil)
                service.observeValue(forKeyPath: "outputVolume", of: nil, change: [.oldKey: NSNumber(value: 0.5625), .newKey: NSNumber(value: 0.5)], context: nil)
                #expect(await waitUntil { server.received(type: 21).count == 2 })
                #expect(server.received(type: 21).map(\.packet.payload) == [[3], [2]])
                #expect(server.received(type: 60).isEmpty)
            }
        }

        @Test("a failed first connection stops with an explanation and isn't retried")
        func failedFirstConnection() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            server.setState(.silent)
            var timing = ConnectionTiming()
            timing.connectTimeout = 2
            try await withTracking(port: server.port, timing: timing) { _, ui in
                #expect(await waitUntil(4) { ui.lastState == "failed" })
                #expect(ui.states == ["connecting", "not connected", "failed"])
                #expect(ui.failures == ["Couldn't connect to 127.0.0.1"])
                #expect(ui.localNetwork.isEmpty)
                #expect(appLog.contains("Connecting Failed"))
                #expect(FakeHardware.events.contains("auto-lock allowed"))
                #expect(FakeHardware.events.contains("background stopped"))

                let failed = Date()
                server.setState(.up)
                await pause(2)
                #expect(server.received(type: 3, after: failed.addingTimeInterval(0.3)).isEmpty)
            }
        }

        @Test("connects by computer name, over IPv4")
        func connectsByName() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            //localhost also means ::1 (IPv6), where the fake server doesn't listen: this only connects over IPv4
            try await withTracking(host: "localhost", port: server.port) { _, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                #expect(await waitUntil { appLog.contains("SlimeVR server detected") })
            }
        }

        @Test("an unknown computer name is reported clearly")
        func unknownName() async throws {
            var timing = ConnectionTiming()
            timing.connectTimeout = 3
            //.invalid never resolves (RFC 2606)
            try await withTracking(host: "owotrack-test.invalid", port: 6969, timing: timing) { _, ui in
                #expect(await waitUntil(5) { ui.lastState == "failed" })
                #expect(ui.failures == ["Couldn't connect to owotrack-test.invalid"])
                #expect(appLog.contains("Can't find a computer named \"owotrack-test.invalid\" on the network"))
            }
        }

        //the app saves the local port and asks for it on the next connection (old SlimeVR versions told trackers apart by port).
        //this checks the app's part only: in the simulator, iOS ignores the asked-for port (tried with 0.0.0.0, any and 127.0.0.1)
        @Test("the local port is saved and asked for on the next connection")
        func localPortSaved() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { _, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
            }
            let firstPort = try #require(server.received(type: 3).last?.sourcePort)
            #expect(UserDefaults.standard.string(forKey: BIND_PORT_USERDEFAULTS_KEY) == String(firstPort))

            try await withTracking(port: server.port, keepSavedPort: true) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                let connection = try #require(service.client?.connection as? NWConnectionUDPClient)
                #expect(connection.bindPort?.rawValue == firstPort)
                guard case .hostPort(_, let asked) = connection.connection?.parameters.requiredLocalEndpoint else {
                    Issue.record("the second connection didn't ask for a local port")
                    return
                }
                #expect(asked.rawValue == firstPort)
            }
            let secondPort = try #require(server.received(type: 3).last?.sourcePort)
            #expect(UserDefaults.standard.string(forKey: BIND_PORT_USERDEFAULTS_KEY) == String(secondPort))
        }
    }
}
