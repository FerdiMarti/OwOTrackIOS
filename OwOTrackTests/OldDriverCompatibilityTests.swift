//
//  OldDriverCompatibilityTests.swift
//  OwOTrackTests
//
//  The app must keep working with the old owoTrack PC driver, not only with SlimeVR.
//  These tests connect to a fake server that behaves like that driver.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Old owoTrack driver compatibility", .timeLimit(.minutes(1)))
    struct OldDriver {

        @Test("connects with the short handshake after SlimeVR's handshake went unanswered")
        func connects() async throws {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            try await withTracking(port: server.port) { _, ui in
                #expect(await waitUntil(5) { ui.lastState == "connected" })
                #expect(await waitUntil { ui.serverTypes == [.owoTrackDriver] })   //recognised by its answer to the short handshake
                let handshakes = server.received(type: 3)
                //7 SlimeVR handshakes the driver can't read, then the short one it answers
                #expect(handshakes.prefix(7).allSatisfy { $0.raw.count > 28 })
                #expect(handshakes.count >= 8)
                #expect(handshakes.dropFirst(7).allSatisfy { $0.raw.count <= 28 })
            }
        }

        @Test("gets only packets it knows, never SlimeVR-only ones")
        func onlyKnownPackets() async throws {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil(5) { ui.lastState == "connected" })
                let client = try #require(service.client)
                for _ in 0..<10 {
                    client.provideRot(rot: floats(0, 0, 0, 1))
                    client.provideGyro(gyro: floats(0, 0, 0.5))
                    client.provideAccel(accel: floats(0, 0, -9.81))
                }
                client.provideButtonPushed(volumeUp: true)
                client.provideButtonPushed(volumeUp: false)
                client.provideBatteryLevel(level: 0.5)
                #expect(await waitUntil { server.received(type: 60).count == 2 })
                await pause(0.3)
                let types = Set(server.received.map(\.packet.type))
                //handshake, rotation, gyro, acceleration, battery, sensor description (ignored by the driver), button, magnetometer state
                #expect(types.isSubset(of: [1, 2, 3, 4, 12, 15, 60, 61]))
                #expect(types.isSuperset(of: [1, 2, 4, 60, 61]))
            }
        }

        @Test("its magnetometer switch works in both directions")
        func magnetometerSwitch() async throws {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil(5) { ui.lastState == "connected" })
                //the app tells the driver whether the magnetometer is on when connecting
                #expect(await waitUntil { server.received(type: 61).last?.packet.payload == [0, UInt8(ascii: "y")] })
                let client = try #require(service.client)
                client.processReceivedData(data: driverPacket(type: 62, payload: [0, UInt8(ascii: "n")]), recursion: false)
                #expect(service.magnetometer == false)
                #expect(ui.magnetometerToggles == [false])
            }
        }
    }
}
