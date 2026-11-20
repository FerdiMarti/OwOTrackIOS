//
//  ReconnectTests.swift
//  OwOTrackTests
//
//  A working connection that's lost is retried until it's back, the user disconnects or the time limit is up.
//  The timings are shortened (fastTiming): a lost connection is noticed after 1.5 s instead of 10.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Reconnecting", .timeLimit(.minutes(1)))
    struct Reconnect {

        @Test("after SlimeVR was quit and started again", arguments: [FakeServer.State.closed, .silent])
        func afterServerOutage(outage: FakeServer.State) async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port, timing: fastTiming) { service, ui in
                #expect(await waitUntil { appLog.contains("SlimeVR server detected") })
                server.setState(outage)     //closed: SlimeVR quit. silent: the Wi-Fi is gone
                #expect(await waitUntil(5) { ui.lastState == "reconnecting" })
                //the screen shows when reconnecting gives up
                let deadline = try #require(ui.reconnectDeadline)
                #expect(abs(deadline.timeIntervalSinceNow - fastTiming.reconnectTimeLimit) < 3)
                #expect(appLog.contains("Connection with server lost"))
                #expect(FakeHardware.events.last == "background started")     //the session stays up while reconnecting

                await pause(1)
                let back = Date()
                server.setState(.up)
                #expect(await waitUntil(8) { ui.lastState == "connected" })
                #expect(ui.states == ["connecting", "connected", "reconnecting", "connected"])
                #expect(appLog.contains("Reconnected"))

                //a fresh start with the server: new handshake, sensor description acknowledged again, SlimeVR packets
                #expect(!server.received(type: 3, after: back).isEmpty)
                #expect(await waitUntil { appLog.components(separatedBy: "SlimeVR server detected").count == 3 })
                #expect(ui.serverTypes == [.slimeVR, .slimeVR])
                let client = try #require(service.client)
                client.provideRot(rot: floats(0, 0, 0, 1))
                #expect(await waitUntil { !server.received(type: 17, after: back).isEmpty })
            }
        }

        @Test("to the old driver, with its short handshake and packets")
        func toOldDriver() async throws {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            try await withTracking(port: server.port, timing: fastTiming) { service, ui in
                #expect(await waitUntil(5) { ui.lastState == "connected" })
                server.setState(.closed)
                #expect(await waitUntil(5) { ui.lastState == "reconnecting" })
                let back = Date()
                server.setState(.up)
                #expect(await waitUntil(10) { ui.lastState == "connected" })
                let client = try #require(service.client)
                client.provideRot(rot: floats(0, 0, 0, 1))
                #expect(await waitUntil { !server.received(type: 1, after: back).isEmpty })
                #expect(server.received(type: 17).isEmpty)
            }
        }

        @Test("Disconnect while reconnecting stops for good")
        func disconnectWhileReconnecting() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port, timing: fastTiming) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                server.setState(.silent)
                #expect(await waitUntil(5) { ui.lastState == "reconnecting" })
                await pressDisconnect(service)
                let stopped = Date()
                #expect(ui.lastState == "not connected")
                #expect(FakeHardware.events.suffix(3) == ["auto-lock allowed", "volume buttons off", "background stopped"])

                server.setState(.up)
                await pause(2)
                #expect(server.received(after: stopped.addingTimeInterval(0.3)).isEmpty)
                #expect(ui.lastState == "not connected")
            }
        }

        @Test("gives up after the time limit")
        func givesUp() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            var timing = fastTiming
            timing.reconnectTimeLimit = 3
            try await withTracking(port: server.port, timing: timing) { _, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                server.setState(.silent)
                #expect(await waitUntil(5) { ui.lastState == "reconnecting" })
                #expect(await waitUntil(10) { ui.lastState == "failed" })
                #expect(ui.failures == ["Couldn't reconnect for 3 seconds"])
                #expect(appLog.contains("Couldn't reconnect for 3 seconds, stopped trying"))
                #expect(FakeHardware.events.suffix(3) == ["auto-lock allowed", "volume buttons off", "background stopped"])

                let gaveUp = Date()
                server.setState(.up)
                await pause(2)
                #expect(server.received(type: 3, after: gaveUp.addingTimeInterval(0.3)).isEmpty)
            }
        }

        @Test("Disconnect and Connect right after each other leave a single connection")
        func disconnectAndConnect() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port, timing: fastTiming) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                server.setState(.silent)
                #expect(await waitUntil(5) { ui.lastState == "reconnecting" })

                //the reconnect loop of the first session is still running when the second session starts
                await MainActor.run {
                    service.stop()
                    service.start(ipAdress: "127.0.0.1", port: String(server.port), magnetometer: true, connectUI: ui)
                }
                server.setState(.up)
                #expect(await waitUntil(6) { ui.lastState == "connected" })
                await pause(fastTiming.reconnectPause + 1)
                #expect(ui.lastState == "connected")
                #expect(!appLog.contains("Reconnected"))    //the old loop gave up, it didn't connect a second client

                let resumed = Date()
                let client = try #require(service.client)
                for _ in 0..<20 {
                    client.provideRot(rot: floats(0, 0, 0, 1))
                }
                #expect(await waitUntil { server.received(type: 17, after: resumed).count == 20 })
                let numbers = server.received(after: resumed).map(\.packet.number)
                #expect(numbers == numbers.sorted())
                #expect(Set(server.received(after: resumed).map(\.sourcePort)).count == 1)
            }
        }
    }
}

extension FakeServer {
    func received(after time: Date) -> [Received] {
        return received.filter { $0.time > time }
    }
}
