//
//  Tracking.swift
//  OwOTrackTests
//

import Foundation
import Testing
@testable import OwOTrack_iOS

//all tests are nested in this suite, which runs them one after another:
//they share the app's logger, the fake hardware's record and the saved local port
@Suite(.serialized) enum OwOTrackTests {}

//timings for the reconnect tests: a lost connection is noticed after 1.5 s instead of 10
let fastTiming = ConnectionTiming(heartbeatTimeout: 1.5, connectTimeout: 4, reconnectPause: 0.5, reconnectTimeLimit: 60)

//a client with a recording connection, as if the handshake had succeeded: what the app sends ends up in connection.packets
func connectedClient() -> (client: UDPGyroProviderClient, connection: RecordingConnection, service: TrackingService) {
    FakeHardware.reset()
    let service = TrackingService(hardware: FakeHardware.self)
    let client = UDPGyroProviderClient(host: "127.0.0.1", port: "6969", service: service)
    let connection = RecordingConnection()
    client.connection = connection
    client.isConnected = true
    service.client = client
    return (client, connection, service)
}

//SlimeVR acknowledges the sensor description: from then on the client talks SlimeVR.
//waits until a rotation goes out as SlimeVR's packet 17, then forgets what was sent so far
func switchToSlimeVR(_ client: UDPGyroProviderClient, _ connection: RecordingConnection) async {
    client.processReceivedData(data: slimeVRPacket(type: 15, payload: [0, 1]), recursion: false)
    client.provideRot(rot: floats(0, 0, 0, 1))
    _ = await waitUntil { connection.packets.contains { $0.type == 17 } }
    connection.clear()
}

//starts tracking with fake hardware, the way the Connect button does it (on the main thread), runs the test and always stops again
func withTracking(host: String = "127.0.0.1", port: UInt16, timing: ConnectionTiming = ConnectionTiming(),
                  keepSavedPort: Bool = false,
                  _ test: (TrackingService, RecordingUI) async throws -> Void) async throws {
    FakeHardware.reset()
    Logger.getInstance().reset()    //else a test waiting for a log line could see it from the test before
    if !keepSavedPort {
        UserDefaults.standard.removeObject(forKey: BIND_PORT_USERDEFAULTS_KEY)
    }
    let service = TrackingService(hardware: FakeHardware.self)
    service.timing = timing
    let ui = RecordingUI()
    await MainActor.run {
        service.start(ipAdress: host, port: String(port), magnetometer: true, connectUI: ui)
    }
    do {
        try await test(service, ui)
    } catch {
        await MainActor.run { service.stop() }
        throw error
    }
    await MainActor.run { service.stop() }
    await pause(0.3)    //let the connection close before the next test
}

//the user presses Disconnect, or Disconnect and Connect right after each other
func pressDisconnect(_ service: TrackingService) async {
    await MainActor.run { service.stop() }
}
