//
//  RelayTests.swift
//  OwOTrackTests
//
//  The Apple Watch tracks through the iPhone app: the watch side (RelayClient) and the iPhone side (RelayHost)
//  talk over a loopback instead of WatchConnectivity, and the iPhone connects to the fake server for the watch.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Relay for the Apple Watch", .timeLimit(.minutes(1)))
    @MainActor
    struct Relay {

        @Test("messages and motion readings arrive as they were sent")
        func packets() {
            let messages: [RelayMessage] = [
                .start(RelayStart(address: "my-pc.local", port: "6969", magnetometer: true, mac: FakeWatchHardware.mac, magnetometerAvailable: false)),
                .stop(session: UUID()), .battery(0.42), .reset(yaw: true), .reset(yaw: false), .alive,
                .status(RelayStatus(state: .reconnecting, serverType: .slimeVR, giveUp: Date(timeIntervalSince1970: 1_000_000), reason: nil, session: UUID())),
                .status(RelayStatus(state: .failed, reason: "Couldn't connect to my-pc.local")),
                .log(["Connecting for the Apple Watch", "Handshake Succeeded"]),
                .vibrate(frequency: 0.25, amplitude: 0.75, duration: 0.5), .magnetometer(false),
                .workout(WorkoutSummary(start: Date(timeIntervalSince1970: 1_000_000), duration: 2712)),
            ]
            for message in messages {
                #expect(RelayPacket(data: RelayPacket(message).data) == .message(message))
            }
            let samples = [
                MotionSample(kind: .rotation, values: [0.1, 0.2, 0.3, 0.9].map { Data(bigEndian: Float($0)) }),
                MotionSample(kind: .acceleration, values: [0, 0, -9.81].map { Data(bigEndian: Float($0)) }),
                MotionSample(kind: .gyro, values: [1, 2, 3].map { Data(bigEndian: Float($0)) }),
            ]
            #expect(RelayPacket(data: RelayPacket(samples: samples).data) == .samples(samples))
            //broken data is ignored, not crashed on
            #expect(RelayPacket(data: Data()) == nil)
            #expect(RelayPacket(data: Data([7, 1, 2])) == nil)
            #expect(RelayPacket(data: Data([1, 1, 0, 0])) == nil)      //a rotation cut short
            #expect(RelayPacket(data: Data([0]) + Data("{".utf8)) == nil)
        }

        @Test("a session the watch saved to Health reaches the iPhone's screen")
        func workoutSaved() async {
            let relay = RelaySetup()
            defer { relay.stop() }
            var received: WorkoutSummary?
            relay.host?.onWorkout = { received = $0 }
            let summary = WorkoutSummary(start: Date(timeIntervalSince1970: 1_000_000), duration: 2712)
            relay.link.watch.send(.workout(summary))        //also when the watch isn't tracking (any more)
            #expect(await waitUntil { received == summary })
        }

        @Test("a saved session's length, in whole minutes")
        func workoutText() {
            #expect(WorkoutSummary(start: Date(), duration: 45 * 60 + 12).durationText == "45 min")
            #expect(WorkoutSummary(start: Date(), duration: 65 * 60).durationText == "1 h 5 min")
            #expect(WorkoutSummary(start: Date(), duration: 20).durationText == "1 min")
        }

        @Test("every control message carries the app's relay version, so apps that can't work together say which to update")
        func versions() throws {
            let message = RelayPacket(.alive).data
            #expect(Array(message.prefix(3)) == [0, RelayProtocol.version, RelayProtocol.oldestPeer])
            #expect(RelayPacket.versions.data == Data([2, RelayProtocol.version, RelayProtocol.oldestPeer]))
            //an app too new or too old for this one: its version is all that's read
            let json = message.dropFirst(3)
            #expect(RelayPacket(data: Data([0, 200, 200]) + json) == .incompatible(peerVersion: 200))
            #expect(RelayPacket(data: Data([2, 0, 0])) == .incompatible(peerVersion: 0))
            //a newer app that still works with this one: a message this one doesn't know is ignored, the rest is read
            #expect(RelayPacket(data: Data([0, 200, RelayProtocol.version]) + Data(#"{"someday":{}}"#.utf8)) == nil)
            #expect(RelayPacket(data: Data([0, 200, RelayProtocol.version]) + json) == .message(.alive))
            #expect(RelayPacket(data: Data([2, RelayProtocol.version, RelayProtocol.oldestPeer])) == nil)

            #expect(RelayPacket.updateHint(peerVersion: 200, onWatch: true) == "Update OwOTrack on this watch")
            #expect(RelayPacket.updateHint(peerVersion: 0, onWatch: true) == "Update OwOTrack on your iPhone")
            #expect(RelayPacket.updateHint(peerVersion: 0, onWatch: false) == "Update OwOTrack on your Apple Watch")
        }

        @Test("a watch app the iPhone app can't work with: both say which app to update")
        func incompatibleApps() async throws {
            let relay = RelaySetup()
            defer { relay.stop() }
            //an old watch app asks to connect: the iPhone answers with its versions and says so on its screen
            let start = RelayPacket(.start(RelayStart(address: "127.0.0.1", port: "6969", magnetometer: true,
                                                     mac: FakeWatchHardware.mac, magnetometerAvailable: false))).data
            relay.link.watch.send(Data([0, 0, 0]) + start.dropFirst(3), onlyIfReachable: false, onConfirmed: nil)
            #expect(await waitUntil { relay.host?.status.reason == "Update OwOTrack on your Apple Watch" })
            #expect(relay.host?.status.state == .failed)
            #expect(relay.link.phone.sentPackets.last == RelayPacket.versions.data)

            //a watch app that's too old for the iPhone's answer gives up with the hint, instead of waiting
            relay.connect(port: 6969)
            relay.link.phone.send(Data([2, 200, 200]), onlyIfReachable: false, onConfirmed: nil)
            #expect(await waitUntil { relay.watchUI.lastState == "failed" })
            #expect(relay.watchUI.failures.last == "Update OwOTrack on this watch")
        }

        @Test("each batch carries only the newest reading of each kind")
        func newestReadings() async throws {
            let server = FakeServer(mode: .oldDriver)       //the old driver also gets the gyro
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            await pause(0.1)
            let before = relay.link.watch.sentSamples.count
            for step in 1...5 {         //faster than a batch: all of them wait for the same one
                relay.watchMotion.emit(rotation: [0, 0, Float(step) / 10, 1])
                relay.watchMotion.emit(gyro: [Float(step), 0, 0])
            }
            #expect(await waitUntil { relay.link.watch.sentSamples.count > before })
            let batch = Array(relay.link.watch.sentSamples.dropFirst(before))
            #expect(batch.map(\.kind) == [.rotation, .gyro])
            #expect(batch.first?.values == [0, 0, 0.5, 1].map { Data(bigEndian: Float($0)) })
            #expect(batch.last?.values == [5, 0, 0].map { Data(bigEndian: Float($0)) })
        }

        @Test("the watch connects through the iPhone, as a tracker of its own")
        func connects() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            let savedAddress = UserDefaults.standard.string(forKey: IP_USERDEFAULTS_KEY)
            relay.connect(port: server.port)

            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            #expect(server.lastHandshake?.mac == "02:0E:57:00:00:02")        //the watch's MAC, not the iPhone's
            #expect(server.lastHandshake?.firmware.hasPrefix("owoTrack watchOS ") == true)     //SlimeVR shows it's the watch
            #expect(await waitUntil { relay.watchUI.serverTypes.last == .slimeVR })
            #expect(relay.watchHardware.events.first == "workout started")
            #expect(relay.watchMotion.startModes == [true])
            #expect(relay.host?.status.state == .connected)

            //the watch's readings and battery level reach SlimeVR
            let before = Date()
            let rotation: [Float] = [0.1, 0.2, 0.3, 0.9]
            relay.watchMotion.emit(rotation: rotation)
            #expect(await waitUntil { !server.received(type: 17, after: before).isEmpty })
            #expect(server.received(type: 17, after: before).first?.packet.payload == [0, 1] + rotation.flatMap { bytes($0) } + [0])
            #expect(await waitUntil { server.received(type: 12).contains { $0.packet.payload == bytes(FakeWatchHardware.batteryLevel) } })

            //SlimeVR doesn't use gyro readings: the watch doesn't send them, which saves a third of the data
            relay.watchMotion.emit(gyro: [1, 2, 3])
            relay.watchMotion.emit(rotation: rotation)
            #expect(await waitUntil { server.received(type: 17, after: before).count >= 2 })
            #expect(!relay.link.watch.sentSamples.contains { $0.kind == .gyro })

            //the iPhone's log for the watch's connection shows on the watch; the iPhone's own saved address stays
            #expect(await waitUntil { relay.watchLog.get().contains("SlimeVR server detected") })
            #expect(UserDefaults.standard.string(forKey: IP_USERDEFAULTS_KEY) == savedAddress)
            //and every so often how fast the readings arrive, to see what the connection to the watch manages
            #expect(await waitUntil(4) { relay.watchLog.get().contains("From the watch:") })
            #expect(await waitUntil(4) { relay.watchLog.get().contains("To the iPhone:") })
        }

        @Test("a slow connection to the iPhone means bigger batches, not a growing queue")
        func slowConnection() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })

            //confirmations stop coming: at most 3 batches go on their way meanwhile
            relay.link.watch.link.confirms = false
            let before = relay.link.watch.sentBatches
            for _ in 0..<10 {
                relay.watchMotion.emit(rotation: [0, 0, 0, 1])
                await pause(0.03)
            }
            #expect(relay.link.watch.sentBatches - before <= 3)

            //unconfirmed ones stop holding up the next after a while, and everything still arrives at the server
            let later = Date()
            relay.watchMotion.emit(rotation: [0, 0, 0, 1])
            #expect(await waitUntil { !server.received(type: 17, after: later).isEmpty })
            #expect(await waitUntil(4) { unconfirmedCounts(relay.watchLog).contains { $0 > 0 } })

            //confirmations again: batches go every 20 ms again
            relay.link.watch.link.confirms = true
            await pause(0.6)
            let resumed = relay.link.watch.sentBatches
            for _ in 0..<10 {
                relay.watchMotion.emit(rotation: [0, 0, 0, 1])
                await pause(0.03)
            }
            #expect(relay.link.watch.sentBatches - resumed >= 6)
        }

        @Test("with the owoTrack driver, the watch sends its gyro readings too")
        func gyroForDriver() async throws {
            let server = FakeServer(mode: .oldDriver)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            let before = Date()
            relay.watchMotion.emit(gyro: [1, 2, 3])
            #expect(await waitUntil { !server.received(type: 2, after: before).isEmpty })
        }

        @Test("resets from the watch reach SlimeVR")
        func resets() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.serverTypes.last == .slimeVR })
            relay.watch.sendReset(yaw: true)
            relay.watch.sendReset(yaw: false)
            #expect(await waitUntil { server.received(type: 21).count == 2 })
            #expect(server.received(type: 21).map(\.packet.payload) == [[3], [2]])      //yaw reset, full reset
        }

        @Test("SlimeVR switches the watch's magnetometer: the watch measures differently and its switch follows")
        func magnetometer() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.serverTypes.last == .slimeVR })
            //the setting it already has: confirmed, but the readings don't restart (that made the yaw jump)
            server.send(type: 25, payload: [0, 0, 1, 1])
            #expect(await waitUntil { server.received(type: 24).count == 1 })
            server.send(type: 25, payload: [0, 0, 1, 0])        //sensor 0, magnetometer, off
            #expect(await waitUntil { relay.watchMotion.startModes == [true, false] })
            #expect(relay.watchUI.magnetometerToggles == [false])
            #expect(await waitUntil { server.received(type: 24).count == 2 })
            #expect(server.received(type: 24).map(\.packet.payload) == [[0, 0, 1], [0, 0, 1]])
        }

        @Test("connecting fails for the watch: the iPhone ends the session with the reason, and the next Connect works")
        func failedConnect() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            server.setState(.silent)
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(8) { relay.watchUI.lastState == "failed" })
            #expect(relay.watchUI.failures == ["Couldn't connect to 127.0.0.1"])
            #expect(relay.watchUI.states.suffix(2) == ["connecting", "failed"])     //no "not connected" without the reason
            #expect(relay.host?.status.state == .failed)
            //the iPhone stopped: no more status messages, and the reason isn't replaced by "lost contact with the watch"
            let statuses = relay.link.phone.sentMessages.filter(\.isStatus).count
            await pause(3.5)        //longer than the iPhone waits for the watch in the tests (3 s)
            #expect(relay.link.phone.sentMessages.filter(\.isStatus).count == statuses)
            #expect(relay.host?.status.reason == "Couldn't connect to 127.0.0.1")

            //the old session's failure, arriving late, doesn't end the new one
            server.setState(.up)
            let oldFailure = try #require(relay.link.phone.sentMessages.last { $0.isStatus })
            relay.connect(port: server.port)
            relay.link.phone.send(oldFailure)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            #expect(relay.watchUI.failures.count == 1)
        }

        @Test("a late Stop of an earlier session doesn't end the next one")
        func staleStop() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.watch.stop()
            let oldStop = try #require(relay.link.watch.sentMessages.last { $0.isStop })
            #expect(await waitUntil { relay.host?.status.state == .notConnected })
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.link.watch.send(oldStop)
            await pause(0.5)
            #expect(relay.host?.status.state == .connected)
            #expect(relay.watchUI.lastState == "connected")
        }

        @Test("the iPhone gives up reconnecting for the watch: the watch gets the reason")
        func reconnectGivesUp() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let timing = ConnectionTiming(heartbeatTimeout: 1.5, connectTimeout: 1, reconnectPause: 0.3, reconnectTimeLimit: 3)
            let relay = RelaySetup(connectionTiming: timing)
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            server.setState(.closed)        //SlimeVR quit
            #expect(await waitUntil(4) { relay.watchUI.lastState == "reconnecting" })
            #expect(await waitUntil(8) { relay.watchUI.lastState == "failed" })
            #expect(relay.watchUI.failures == ["Couldn't reconnect for 3 seconds"])
            #expect(relay.watchUI.states.suffix(2) == ["reconnecting", "failed"])
            #expect(relay.host?.status.state == .failed)
            #expect(relay.host?.status.reason == "Couldn't reconnect for 3 seconds")
            #expect(relay.watchHardware.events.last == "workout ended")
        }

        @Test("the iPhone stays out of reach: the watch gives up after a while")
        func iPhoneGone() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.link.watch.link.isUp = false
            #expect(await waitUntil(4) { relay.watchUI.lastState == "reconnecting" })
            #expect(await waitUntil(9) { relay.watchUI.lastState == "failed" })     //after 6 s in the tests
            #expect(relay.watchUI.failures == ["Couldn't reach the iPhone for 6 seconds"])
            #expect(relay.watchHardware.events.last == "workout ended")
        }

        @Test("the watch picks one of several servers the iPhone found, and connects to it through the iPhone")
        func serverChoice() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let servers = [FoundServer(address: "127.0.0.1", type: .slimeVR), FoundServer(address: "192.168.1.40", type: .owoTrackDriver)]
            let relay = RelaySetup(finder: FakeFinder(result: ServerSearchResult(servers: servers)))
            defer { relay.stop() }
            //the watch's connect screen saves the server it connects to: put the saved settings back afterwards
            let keys = [IP_USERDEFAULTS_KEY, PORT_USERDEFAULTS_KEY, MAGNETOMETER_USERDEFAULTS_KEY, RECENT_SERVERS_USERDEFAULTS_KEY]
            let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
            defer { zip(keys, saved).forEach { UserDefaults.standard.set($1, forKey: $0) } }

            let model = ConnectionModel(service: relay.watch, sharing: nil)       //searches through the iPhone too
            model.port = String(server.port)
            model.ip = ""
            model.connectPressed()
            #expect(await waitUntil(5) { model.serverChoices == servers })
            model.chooseServer(nil)                 //SwiftUI may close the list before it runs the button's action
            model.chooseServer(servers[0])
            #expect(await waitUntil(5) { model.isConnected })
            #expect(relay.host?.status.state == .connected)
            #expect(server.lastHandshake?.mac == "02:0E:57:00:00:02")
        }

        @Test("asking twice for the same session doesn't connect twice")
        func repeatedStart() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            let start = try #require(relay.link.watch.sentMessages.first { $0.isStart })
            relay.link.watch.send(start)        //the watch asked again before the iPhone answered
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            #expect(relay.watchLog.get().components(separatedBy: "Connecting for the Apple Watch").count == 2)
        }

        @Test("a Stop on the iPhone that the watch missed isn't undone when the watch asks again")
        func missedStop() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.link.watch.link.isUp = false
            relay.host?.stop(tellWatch: true)       //lost on the way
            relay.link.watch.link.isUp = true
            //the watch hears nothing more and asks for its session again: it gets the Stop again instead of a new connection
            #expect(await waitUntil(6) { relay.watchUI.lastState == "not connected" })
            #expect(relay.watchLog.get().contains("Stopped on the iPhone"))
            #expect(relay.host?.status.state == .notConnected)
            #expect(relay.watchUI.failures.isEmpty)
        }

        @Test("vibrations from the server reach the watch")
        func vibration() async throws {
            let server = FakeServer(mode: .oldDriver)       //it sends vibrations
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            //duration, frequency, amplitude, as the owoTrack driver sends them
            server.sendRaw(driverPacket(type: 2, payload: littleEndianBytes(Float(0.5)) + littleEndianBytes(Float(0.25)) + littleEndianBytes(Float(0.75))))
            #expect(await waitUntil { relay.watchHardware.events.contains("vibrate f=0.25 a=0.75 d=0.5") })
        }

        @Test("Disconnect on the watch ends its connection on the iPhone")
        func disconnectOnWatch() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.watch.stop()
            #expect(relay.watchUI.lastState == "not connected")
            #expect(relay.watchHardware.events.last == "workout ended")
            #expect(await waitUntil { relay.host?.status.state == .notConnected })
            let stopped = Date()
            await pause(1)
            #expect(server.received(after: stopped.addingTimeInterval(0.3)).isEmpty)
        }

        @Test("Stop on the iPhone ends the watch's session")
        func stopOnPhone() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            relay.host?.stop(tellWatch: true)
            #expect(await waitUntil { relay.watchUI.lastState == "not connected" })
            #expect(relay.watchHardware.events.last == "workout ended")
            #expect(relay.watchLog.get().contains("Stopped on the iPhone"))       //the watch's log says why
            #expect(relay.watchUI.failures.isEmpty)
        }

        @Test("the iPhone and the watch track at the same time, as two trackers")
        func phoneAndWatch() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            try await withTracking(port: server.port) { service, phoneUI in
                #expect(await waitUntil { phoneUI.lastState == "connected" })
                let relay = RelaySetup()
                defer { relay.stop() }
                relay.connect(port: server.port)
                #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })

                let handshakes = server.received(type: 3)
                let macs = Set(handshakes.compactMap { SlimeVRHandshake(packet: $0.raw)?.mac })
                #expect(macs == ["02:0E:57:00:00:01", "02:0E:57:00:00:02"])
                let firmware = handshakes.compactMap { SlimeVRHandshake(packet: $0.raw) }.map { $0.firmware.components(separatedBy: " ").prefix(2).joined(separator: " ") }
                #expect(Set(firmware) == ["owoTrack iOS", "owoTrack watchOS"])
                #expect(Set(handshakes.map(\.sourcePort)).count == 2)

                //the watch stops; the iPhone keeps tracking
                relay.watch.stop()
                #expect(await waitUntil { relay.host?.status.state == .notConnected })
                let after = Date()
                try #require(service.client).provideRot(rot: floats(0, 0, 0, 1))
                #expect(await waitUntil { !server.received(type: 17, after: after).isEmpty })
                #expect(phoneUI.lastState == "connected")
            }
        }

        @Test("a watch without motion readings or battery level (like the simulator) stays connected")
        func quietWatch() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.watchHardware.reportsBattery = false
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            await pause(4.5)        //longer than the iPhone waits for the watch in the tests (3 s)
            #expect(relay.host?.status.state == .connected)
            #expect(relay.watchUI.lastState == "connected")
            #expect(relay.link.watch.sentMessages.contains(.alive))
        }

        @Test("without the iPhone app, the watch explains what to do")
        func noPhoneApp() async {
            let relay = RelaySetup(withHost: false)
            defer { relay.stop() }
            relay.connect(port: 6969)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "failed" })
            #expect(relay.watchUI.failures.first == "Open OwOTrack on your iPhone, then connect again")
            #expect(relay.watchHardware.events.last == "workout ended")
            //it kept asking meanwhile, which wakes the iPhone app if it's there, and called it off when it gave up
            #expect(relay.link.watch.sentMessages.filter(\.isStart).count >= 3)
            #expect(relay.link.watch.sentMessages.last?.isStop == true)
        }

        @Test("the iPhone out of reach: the watch shows reconnecting, and continues when it's back")
        func iPhoneOutOfReach() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })

            relay.link.watch.link.isUp = false
            #expect(await waitUntil(4) { relay.watchUI.lastState == "reconnecting" })
            //meanwhile the iPhone hears nothing from the watch and ends its connection
            #expect(await waitUntil(4) { relay.host?.status.state == .failed })

            relay.link.watch.link.isUp = true
            #expect(await waitUntil(5) { relay.watchUI.lastState == "connected" })
            #expect(relay.host?.status.state == .connected)
            #expect(relay.watchLog.get().contains("Connected to the iPhone again"))
        }

        @Test("the watch goes quiet: the iPhone ends its connection to the server")
        func watchGoesQuiet() async throws {
            let server = FakeServer(mode: .slimeVR)
            defer { server.stop() }
            let relay = RelaySetup()
            defer { relay.stop() }
            relay.connect(port: server.port)
            #expect(await waitUntil(5) { relay.host?.status.state == .connected })
            relay.link.watch.link.isUp = false
            #expect(await waitUntil(5) { relay.host?.status.state == .failed })
            #expect(relay.host?.status.reason == "The iPhone lost contact with the watch")      //shown on the iPhone
            let ended = Date()
            await pause(1.5)
            #expect(server.received(after: ended.addingTimeInterval(0.3)).isEmpty)
        }

        @Test("keeping the iPhone awake is shared: on with the first session, off after the last")
        func sharedSwitch() {
            var switched: [String] = []
            let keepAwake = SharedSwitch(on: { switched.append("on") }, off: { switched.append("off") })
            keepAwake.acquire()     //the iPhone tracks
            keepAwake.acquire()     //and relays the watch
            keepAwake.release()     //the watch stops
            #expect(switched == ["on"])
            #expect(keepAwake.isOn)
            keepAwake.release()     //the iPhone stops
            keepAwake.release()     //one release too many is ignored
            #expect(switched == ["on", "off"])
            #expect(!keepAwake.isOn)
        }
    }
}

//the unconfirmed counts in the watch's "To the iPhone: … ms there and back, 2 of 40 messages unconfirmed" lines
private func unconfirmedCounts(_ log: Logger) -> [Int] {
    return log.get().split(separator: "\n").compactMap { line -> Int? in
        guard line.hasPrefix("To the iPhone:"), let range = line.range(of: "there and back, ") else {
            return nil
        }
        return Int(line[range.upperBound...].prefix { $0.isNumber })
    }
}

extension RelayMessage {
    var isStart: Bool {
        if case .start = self {
            return true
        }
        return false
    }

    var isStop: Bool {
        if case .stop = self {
            return true
        }
        return false
    }

    var isStatus: Bool {
        if case .status = self {
            return true
        }
        return false
    }
}
