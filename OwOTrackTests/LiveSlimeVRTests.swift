//
//  LiveSlimeVRTests.swift
//  OwOTrackTests
//
//  Optional: connects to a real SlimeVR server. Only runs when SLIMEVR_HOST is set to its IP address
//  (SLIMEVR_PORT if it isn't 6969):
//    - Xcode: Product → Scheme → Edit Scheme → Test → Arguments → Environment Variables, enable SLIMEVR_HOST and enter the IP
//    - Terminal: TEST_RUNNER_SLIMEVR_HOST=192.168.1.20 xcodebuild test -scheme OwOTrack -destination 'platform=iOS Simulator,name=iPhone 17'
//  It shows up in SlimeVR as the test tracker 02:0E:57:00:00:01 and sends no resets.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

enum LiveServer {
    static var host: String? {
        guard let host = ProcessInfo.processInfo.environment["SLIMEVR_HOST"], !host.isEmpty else {
            return nil
        }
        return host
    }

    static var port: UInt16 {
        return UInt16(ProcessInfo.processInfo.environment["SLIMEVR_PORT"] ?? "") ?? 6969
    }
}

extension OwOTrackTests {
    @Suite("Live SlimeVR server", .enabled(if: LiveServer.host != nil, "set SLIMEVR_HOST to the IP address of a running SlimeVR server"),
           .timeLimit(.minutes(1)))
    struct LiveSlimeVR {

        @Test("a search of this Mac's network finds the server")
        func searchFindsServer() async throws {
            let host = try #require(LiveServer.host)
            let finder = LocalServerFinder(mac: FakeHardware.testMac, platform: "iOS")       //the test tracker, not a new one
            let result = await withCheckedContinuation { continuation in
                finder.findServers(port: String(LiveServer.port)) { continuation.resume(returning: $0) }
            }
            #expect(result.failure == nil)
            #expect(result.servers.contains(FoundServer(address: host, type: .slimeVR)), "found: \(result.servers)")
        }

        @Test("connects, is recognised as SlimeVR and stays connected while sending data")
        func connectsAndStreams() async throws {
            let host = try #require(LiveServer.host)
            try await withTracking(host: host, port: LiveServer.port) { service, ui in
                #expect(await waitUntil(6) { ui.lastState == "connected" }, "no connection to SlimeVR at \(host):\(LiveServer.port)")
                #expect(await waitUntil(5) { appLog.contains("SlimeVR server detected") }, "SlimeVR didn't acknowledge the sensor description")
                let client = try #require(service.client)

                //5 seconds of data, like a tracker lying still, plus the battery level
                client.provideBatteryLevel(level: FakeHardware.batteryLevel)
                for _ in 0..<50 {
                    client.provideRot(rot: floats(0, 0, 0, 1))
                    client.provideAccel(accel: floats(0, 0, 0))
                    await pause(0.1)
                }
                #expect(client.isConnected)
                #expect(Date().timeIntervalSince1970 - client.lastHeartbeat < 3, "SlimeVR stopped answering")
                #expect(ui.states == ["connecting", "connected"])
                #expect(!appLog.contains("Connection with server lost"))
            }
        }
    }
}
