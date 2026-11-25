//
//  RelayFakes.swift
//  OwOTrackTests
//
//  The relay between watch and iPhone in one process: a loopback instead of WatchConnectivity,
//  and fakes for the watch's hardware and motion sensors.
//

import Foundation
import CoreLocation
@testable import OwOTrack_iOS

//connects the watch side and the iPhone side directly. The link can be cut, like the devices getting out of range
final class LoopbackTransport: RelayTransport {
    final class Link {
        private let lock = NSLock()
        private var up = true
        private var confirming = true

        var isUp: Bool {
            get { lock.lock(); defer { lock.unlock() }; return up }
            set { lock.lock(); up = newValue; lock.unlock() }
        }

        //false: messages arrive, but their confirmations don't (a slow connection)
        var confirms: Bool {
            get { lock.lock(); defer { lock.unlock() }; return confirming }
            set { lock.lock(); confirming = newValue; lock.unlock() }
        }
    }

    var onReceive: ((Data) -> Void)?
    var replyProvider: (() -> Data?)?
    var onReply: ((Data) -> Void)?
    weak var other: LoopbackTransport?
    let link: Link
    //true: what this end sends by itself gets lost, but its answers to the other end's messages still arrive.
    //Like an iPhone whose iOS doesn't consider the watch app reachable
    var losesOwnMessages = false
    private let lock = NSLock()
    private var sentData: [Data] = []

    init(link: Link) {
        self.link = link
    }

    //a watch end and an iPhone end
    static func pair() -> (watch: LoopbackTransport, phone: LoopbackTransport) {
        let link = Link()
        let watch = LoopbackTransport(link: link)
        let phone = LoopbackTransport(link: link)
        watch.other = phone
        phone.other = watch
        return (watch, phone)
    }

    var isReachable: Bool {
        return link.isUp && other?.onReceive != nil
    }

    //like WatchConnectivity: delivered later, on the main thread, and lost while the link is down
    @discardableResult
    func send(_ data: Data, onlyIfReachable: Bool, onConfirmed: ((Bool) -> Void)?) -> Bool {
        lock.lock()
        sentData.append(data)
        lock.unlock()
        guard link.isUp, let other = other else {
            return false
        }
        let link = self.link
        if losesOwnMessages {
            DispatchQueue.main.async {
                onConfirmed?(false)
            }
            return true
        }
        DispatchQueue.main.async {
            other.onReceive?(data)
            if link.confirms, let onConfirmed = onConfirmed {
                //a confirmed message: what the receiver has for the sender comes back with the confirmation
                if let reply = other.replyProvider?(), !reply.isEmpty {
                    (self.onReply ?? self.onReceive)?(reply)
                }
                onConfirmed(true)
            }
        }
        return true
    }

    //everything this end sent, as it went out
    var sentPackets: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sentData
    }

    //how many batches of motion readings this end sent
    var sentBatches: Int {
        lock.lock()
        defer { lock.unlock() }
        return sentData.filter { data in
            if case .samples? = RelayPacket(data: data) { return true }
            return false
        }.count
    }

    //the motion readings this end sent
    var sentSamples: [MotionSample] {
        lock.lock()
        defer { lock.unlock() }
        return sentData.flatMap { data -> [MotionSample] in
            if case .samples(let samples)? = RelayPacket(data: data) { return samples }
            return []
        }
    }

    //the control messages this end sent
    var sentMessages: [RelayMessage] {
        lock.lock()
        defer { lock.unlock() }
        return sentData.compactMap { data in
            if case .message(let message)? = RelayPacket(data: data) { return message }
            return nil
        }
    }
}

//the watch's hardware: records the workout session and vibrations
final class FakeWatchHardware: TrackerHardware {
    static let mac: [UInt8] = [0x02, 0x0E, 0x57, 0x00, 0x00, 0x02]     //not the iPhone's test MAC (…:01)
    static let batteryLevel: Float = 0.6

    private let lock = NSLock()
    private var recorded: [String] = []
    var reportsBattery = true       //false: like the simulator, which doesn't know the battery level

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ event: String) {
        lock.lock()
        recorded.append(event)
        lock.unlock()
    }

    func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        record("vibrate f=\(f) a=\(a) d=\(d)")
        return true
    }
    func vibrate() { record("vibrate") }
    func startBackgroundUsage(target: CLLocationManagerDelegate?) { record("workout started") }
    func stopBackgroundUsage() { record("workout ended") }
    func getBatteryLevel() -> Float? { reportsBattery ? FakeWatchHardware.batteryLevel : nil }
    func getPseudoMacAddress() -> [UInt8] { FakeWatchHardware.mac }
    func registerVolButtonListener(target: NSObject) {}
    func unregisterVolButtonListener(target: NSObject) {}
    func startProximitySensor() {}
    func stopProximitySensor() {}
    func preventAutoLock() {}
    func allowAutoLock() {}
    func startBatteryLevelMonitoring() {}
    func stopBatteryLevelMonitoring() {}
}

//the watch's motion sensors: records how they were started, and emits readings when a test asks
final class FakeMotion: MotionSource {
    let magnetometerCorrectionAvailable = true
    private let lock = NSLock()
    private var sink: MotionSink?
    private var modes: [Bool] = []

    //the magnetometer setting of every start
    var startModes: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return modes
    }

    func startUpdates(sink: MotionSink, useMagn: Bool) {
        lock.lock()
        self.sink = sink
        modes.append(useMagn)
        lock.unlock()
    }

    func stopUpdates() {
        lock.lock()
        sink = nil
        lock.unlock()
    }

    func emit(rotation: [Float]) {
        currentSink?.provideRot(rot: rotation.map { Data(bigEndian: $0) })
    }

    func emit(gyro: [Float]) {
        currentSink?.provideGyro(gyro: gyro.map { Data(bigEndian: $0) })
    }

    private var currentSink: MotionSink? {
        lock.lock()
        defer { lock.unlock() }
        return sink
    }
}

extension RelayHost.Timing {
    static let fastTest = RelayHost.Timing(watchTimeout: 3, statusInterval: 0.5, rateLogInterval: 2, answerStatusInterval: 0.3)
}

extension RelayClient.Timing {
    static let fastTest = RelayClient.Timing(batchInterval: 0.02, firstAnswerTimeout: 3, iPhoneTimeout: 2, retryInterval: 0.5,
                                             giveUp: 6, batteryInterval: 1, heartbeatInterval: 1, confirmTimeout: 0.5, statsInterval: 2,
                                             pauseLength: 2, answersOnlyAfter: 1.5)
}

//a watch and an iPhone app connected by a loopback, with the iPhone's hardware faked by FakeHardware
final class RelaySetup {
    let link = LoopbackTransport.pair()
    let watchHardware = FakeWatchHardware()
    let watchMotion = FakeMotion()
    let watchUI = RecordingUI()
    let watchLog = Logger()
    let watch: RelayClient
    let host: RelayHost?

    //withHost: false is a watch without the iPhone app. finderCandidates: the addresses the iPhone searches for the watch,
    //or finder: what the iPhone finds. connectionTiming: of the iPhone's connection to the server for the watch
    init(withHost: Bool = true, finderCandidates: [String]? = nil, finder: ServerFinding? = nil, connectionTiming: ConnectionTiming = fastTiming) {
        watch = RelayClient(transport: link.watch, hardware: watchHardware, motion: watchMotion, logger: watchLog, timing: .fastTest)
        host = withHost ? RelayHost(transport: link.phone, device: StaticHardware(FakeHardware.self), connectionTiming: connectionTiming, timing: .fastTest,
                                    makeFinder: { mac in
                                        finder ?? LocalServerFinder(mac: mac, platform: "watchOS", candidates: { finderCandidates }, timing: .fastTest)
                                    }) : nil
    }

    func connect(port: UInt16, magnetometer: Bool = true) {
        watch.start(ipAdress: "127.0.0.1", port: String(port), magnetometer: magnetometer, connectUI: watchUI)
    }

    func stop() {
        watch.stop()
        host?.stop(tellWatch: false)
    }
}
