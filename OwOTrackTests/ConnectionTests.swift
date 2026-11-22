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

        @Test("SlimeVR's pings are answered, so it can show the latency")
        func pings() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { _, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                #expect(await waitUntil { server.answeredPings >= 2 })
            }
        }

        @Test("the volume buttons can be switched off, also while tracking")
        func volumeButtonsSwitch() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let defaults = UserDefaults.standard
            defer { defaults.removeObject(forKey: VOLUME_BUTTONS_USERDEFAULTS_KEY) }
            defaults.set(false, forKey: VOLUME_BUTTONS_USERDEFAULTS_KEY)
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                #expect(!FakeHardware.events.contains("volume buttons on"))     //off: the buttons are left alone
                await MainActor.run {
                    defaults.set(true, forKey: VOLUME_BUTTONS_USERDEFAULTS_KEY)
                    service.volumeButtonsSettingChanged()
                }
                #expect(FakeHardware.events.filter { $0.hasPrefix("volume buttons") } == ["volume buttons on"])
                await MainActor.run {
                    defaults.set(false, forKey: VOLUME_BUTTONS_USERDEFAULTS_KEY)
                    service.volumeButtonsSettingChanged()
                }
                #expect(FakeHardware.events.filter { $0.hasPrefix("volume buttons") } == ["volume buttons on", "volume buttons off"])
            }
            //stopping doesn't switch them off a second time
            #expect(FakeHardware.events.filter { $0.hasPrefix("volume buttons") } == ["volume buttons on", "volume buttons off"])
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
                #expect(ui.states == ["connecting", "failed"])     //the reason right away, not "not connected" first
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
        //the simulator ignores the asked-for port, so it never reports it taken: this hands the connection iOS's report
        //from a device directly
        @Test("a saved local port that's taken (e.g. still closing) is replaced by a free one in the same attempt")
        func busyLocalPort() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let key = "bindportTest"
            UserDefaults.standard.set("50123", forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let client = NWConnectionUDPClient(host: "127.0.0.1", port: Int(server.port), portKey: key)
            defer { client.close() }
            client.loadLastPort()
            #expect(client.bindPort?.rawValue == 50123)

            let problems = Recorded<ConnectionProblem>()
            let ready = Recorded<Bool>()
            let taken = NWConnection(host: "127.0.0.1", port: 6969, using: .udp)
            client.handle(.waiting(.posix(.EADDRINUSE)), of: taken, cb: { ready.append(true) }, onProblem: { problems.append($0) })
            #expect(problems.values.map(\.reason) == ["The network port of the last connection was still in use, connecting on a new one"])
            #expect(problems.values.allSatisfy { !$0.fatal })
            #expect(client.bindPort == nil)
            #expect(UserDefaults.standard.string(forKey: key) == nil)
            #expect(client.connection !== taken)
            #expect(client.connection?.parameters.requiredLocalEndpoint == nil)     //any free port
            #expect(await waitUntil { ready.values == [true] })      //the same attempt goes on
            #expect(UserDefaults.standard.string(forKey: key) != nil)      //and the new port is asked for next time
        }

        @Test("the iPhone's and the watch's sessions don't bind the same local port, even if both saved the same one")
        func separatePorts() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            defer { UserDefaults.standard.removeObject(forKey: "bindportWatch") }
            try await withTracking(port: server.port) { service, ui in
                #expect(await waitUntil { ui.lastState == "connected" })
                let phone = try #require(service.client?.connection as? NWConnectionUDPClient)
                guard case .hostPort(_, let phonePort)? = phone.connection?.currentPath?.localEndpoint else {
                    Issue.record("the iPhone's connection has no local port")
                    return
                }
                let watch = NWConnectionUDPClient(host: "127.0.0.1", port: Int(server.port), portKey: "bindportWatch")
                UserDefaults.standard.set(String(phonePort.rawValue), forKey: "bindportWatch")
                watch.loadLastPort()
                #expect(watch.bindPort == nil)          //the iPhone's session uses it: a free one instead
                UserDefaults.standard.set("50124", forKey: "bindportWatch")
                watch.loadLastPort()
                #expect(watch.bindPort?.rawValue == 50124)
            }
        }

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

//values reported from any thread
final class Recorded<Value> {
    private let lock = NSLock()
    private var recorded: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
