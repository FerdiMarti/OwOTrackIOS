//
//  RelayHost.swift
//  OwOTrack
//
//  The iPhone side of the relay: connects to the server for the watch, as a tracker of its own
//  (with the watch's MAC address, separate from the iPhone's own tracker), fed with the watch's motion readings.
//

import Foundation
import CoreLocation

final class RelayHost {
    struct Timing {
        var watchTimeout: TimeInterval = 20     //nothing from the watch for that long: it's gone, end its session
        var statusInterval: TimeInterval = 3    //how often the watch gets the status as a sign of life
        var rateLogInterval: TimeInterval = 60  //how often the log shows how many readings arrive from the watch
    }

    //the watch's connection, for the iPhone's screen. Changed on the main thread
    private(set) var status = RelayStatus(state: .notConnected) {
        didSet {
            if status != oldValue {
                onStatusChange?(status)
            }
        }
    }
    var onStatusChange: ((RelayStatus) -> Void)?
    var onWorkout: ((WorkoutSummary) -> Void)?      //the watch saved a session to Health
    let logger = Logger()       //the watch session's own log, sent to the watch

    private let transport: RelayTransport
    private let device: TrackerHardware
    private let connectionTiming: ConnectionTiming
    private let timing: Timing
    private let makeFinder: ([UInt8]) -> ServerFinding     //searches the network for the watch, with the watch's MAC
    private var service: TrackingService?
    private var hardware: RelayedWatchHardware?
    private var motion: RelayedWatchMotion?
    private var reporter: RelayReporter?
    private var request: RelayStart?
    //how the last session ended when the watch didn't end it itself (stopped on the iPhone, connecting failed):
    //if the watch missed that and asks for the session again, it gets this again instead of a new connection
    private var ended: RelayStatus?
    private var lastHeard = Date.distantPast
    private var lastVersionsSent = Date.distantPast
    private var timer: Timer?
    private var statusSendScheduled = false
    private var receivedSamples = 0             //since rateCountStart: how fast the watch's readings arrive
    private var receivedBatches = 0
    private var rateCountStart = Date()

    //device: the iPhone's own hardware, which keeps the app awake while it relays
    init(transport: RelayTransport, device: TrackerHardware, connectionTiming: ConnectionTiming = ConnectionTiming(), timing: Timing = Timing(),
         makeFinder: @escaping ([UInt8]) -> ServerFinding = { mac in LocalServerFinder(mac: mac, platform: "watchOS") }) {
        self.transport = transport
        self.device = device
        self.connectionTiming = connectionTiming
        self.timing = timing
        self.makeFinder = makeFinder
        transport.onReceive = { [weak self] data in
            self?.receive(data)
        }
    }

    //a packet from the watch. On the main thread
    func receive(_ data: Data) {
        guard let packet = RelayPacket(data: data) else {
            return
        }
        if case .incompatible(let peerVersion) = packet {
            //the watch app's version can't work with this one: the watch learns from this app's versions which app
            //to update (at most once a second, it keeps asking), and this screen says it too
            if service == nil {
                status = RelayStatus(state: .failed, reason: RelayPacket.updateHint(peerVersion: peerVersion, onWatch: false))
            }
            if Date().timeIntervalSince(lastVersionsSent) >= 1 {
                lastVersionsSent = Date()
                _ = transport.send(RelayPacket.versions.data, onlyIfReachable: false, onConfirmed: nil)
            }
            return
        }
        lastHeard = Date()
        switch packet {
        case .samples(let samples):
            motion?.deliver(samples)
            receivedSamples += samples.count
            receivedBatches += 1
        case .message(.start(let request)):
            if service != nil && request.session == self.request?.session {
                transport.send(.status(status))     //already on it: the watch asked again before it heard back, or lost contact for a moment
            } else if let ended = ended, ended.session == request.session {
                transport.send(.status(ended))      //it ended, and the watch missed that
            } else {
                stop(tellWatch: false)
                start(request)
            }
        case .message(.stop(let session)):
            if session == request?.session {
                end(RelayStatus(state: .notConnected), tellWatch: false, final: false)
            }
        case .message(.battery(let level)):
            hardware?.batteryLevel = level
        case .message(.reset(let yaw)):
            service?.sendReset(yaw: yaw)
        case .message(.workout(let summary)):
            onWorkout?(summary)
        case .message(.find(let port, let mac)):
            makeFinder(mac).findServers(port: port) { [weak self] result in
                DispatchQueue.main.async {
                    self?.transport.send(.found(result))
                }
            }
        case .message, .versions, .incompatible:
            break       //messages for the watch
        }
    }

    private func start(_ request: RelayStart) {
        self.request = request
        status = RelayStatus(state: .connecting, session: request.session)
        let hardware = RelayedWatchHardware(device: device, mac: request.mac, transport: transport)
        let motion = RelayedWatchMotion(magnetometerAvailable: request.magnetometerAvailable, transport: transport)
        let service = TrackingService(device: hardware, motion: motion, logger: logger)
        service.timing = connectionTiming
        service.savesSettings = false
        service.localPortKey = "bindportWatch"
        service.firmwarePlatform = "watchOS"       //SlimeVR shows "owoTrack watchOS" as the watch tracker's firmware
        receivedSamples = 0
        receivedBatches = 0
        rateCountStart = Date()
        let reporter = RelayReporter(host: self)
        logger.attachUI(connectUI: reporter)
        self.hardware = hardware
        self.motion = motion
        self.service = service
        self.reporter = reporter
        logger.reset()
        logger.addEntry("Connecting for the Apple Watch")
        service.start(ipAdress: request.address, port: request.port, magnetometer: request.magnetometer, connectUI: reporter)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timing.statusInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    //ends the watch's session: the user stopped it on the iPhone (tellWatch: the watch learns why),
    //or the watch stopped it or asked for a new one
    func stop(tellWatch: Bool) {
        end(RelayStatus(state: .notConnected, reason: tellWatch ? "Stopped on the iPhone" : nil), tellWatch: tellWatch, final: tellWatch)
    }

    //ends the watch's session in the given state, which the watch gets with the reason.
    //final: the watch asking for this session again gets this state again (else the session starts over)
    private func end(_ endState: RelayStatus, tellWatch: Bool, final: Bool) {
        timer?.invalidate()
        timer = nil
        guard let service = service, let request = request else {
            return
        }
        reporter?.detach()      //late reports of this session must not change the next one's status
        reporter = nil
        service.stop()
        self.service = nil
        hardware = nil
        motion = nil
        self.request = nil
        var endState = endState
        endState.session = request.session
        status = endState
        if final {
            ended = endState
        }
        if tellWatch {
            transport.send(.status(endState))
        }
    }

    //a sign of life for the watch, and the end of the session if the watch went quiet
    private func check() {
        if Date().timeIntervalSince(lastHeard) > timing.watchTimeout {
            //shown on the iPhone, and on the watch if it can still hear the iPhone. If the watch comes back, it asks for
            //its session again, which then starts over
            end(RelayStatus(state: .failed, reason: "The iPhone lost contact with the watch"), tellWatch: true, final: false)
            return
        }
        transport.send(.status(status))
        let elapsed = Date().timeIntervalSince(rateCountStart)
        if elapsed >= timing.rateLogInterval {
            logger.addEntry(String(format: "From the watch: %.0f readings per second, in %.1f messages per second",
                                   Double(receivedSamples) / elapsed, Double(receivedBatches) / elapsed))
            receivedSamples = 0
            receivedBatches = 0
            rateCountStart = Date()
        }
    }

    //the session reported a change. Changes in one pass go to the watch together, as the final state.
    //Connecting failed or reconnecting gave up: the session ends here, and the watch gets the reason
    fileprivate func update(_ change: (inout RelayStatus) -> Void) {
        var status = self.status
        change(&status)
        if status.state == .failed {
            end(status, tellWatch: true, final: true)
            return
        }
        status.session = request?.session
        self.status = status
        if !statusSendScheduled {
            statusSendScheduled = true
            DispatchQueue.main.async {
                self.statusSendScheduled = false
                self.transport.send(.status(self.status))
            }
        }
    }

    fileprivate func sendLog(_ lines: [String]) {
        transport.send(.log(lines))
    }
}

//reports the watch session's state and log to the watch (and to the iPhone's screen through RelayHost.status)
private final class RelayReporter: ConnectUI {
    private weak var host: RelayHost?       //only changed on the main thread
    private let lock = NSLock()
    private var sentLines = 0

    init(host: RelayHost) {
        self.host = host
    }

    //the session ended: what it still reports is ignored
    func detach() {
        host = nil
    }

    private func update(_ change: @escaping (inout RelayStatus) -> Void) {
        DispatchQueue.main.async {
            self.host?.update(change)
        }
    }

    func setLoading() {
        update { $0 = RelayStatus(state: .connecting) }
    }

    func setConnected() {
        update {
            $0.state = .connected
            $0.giveUp = nil
            $0.reason = nil
        }
    }

    func setUnconnected() {
        update { $0 = RelayStatus(state: .notConnected, serverType: $0.serverType) }
    }

    func setReconnecting(until giveUp: Date) {
        update {
            $0.state = .reconnecting
            $0.giveUp = giveUp
        }
    }

    func setFailed(_ reason: String) {
        update { $0 = RelayStatus(state: .failed, reason: reason) }
    }

    func setServerType(_ type: ServerType) {
        update { $0.serverType = type }
    }

    func setLocalNetworkAccess(_ access: LocalNetworkAccess) {}

    //the watch learns about a switched magnetometer from RelayedWatchMotion, which also switches its readings
    func setMagnometerToggle(use: Bool) {}

    //called while the Logger holds its lock: only the new lines go to the watch, the Logger isn't called here
    func updateLogs(text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lock.lock()
        let new: [String]
        if lines.count < sentLines {
            new = lines     //the log started over
        } else {
            new = Array(lines.dropFirst(sentLines))
        }
        sentLines = lines.count
        lock.unlock()
        if !new.isEmpty {
            DispatchQueue.main.async {
                self.host?.sendLog(new)
            }
        }
    }
}

//the hardware of the watch's session on the iPhone: the watch's MAC and battery level, vibrations go to the watch,
//and keeping the iPhone awake is shared with the iPhone's own session
final class RelayedWatchHardware: TrackerHardware {
    private let device: TrackerHardware
    private let mac: [UInt8]
    private let transport: RelayTransport
    private let lock = NSLock()
    private var battery: Float?

    init(device: TrackerHardware, mac: [UInt8], transport: RelayTransport) {
        self.device = device
        self.mac = mac
        self.transport = transport
    }

    var batteryLevel: Float? {
        get { lock.lock(); defer { lock.unlock() }; return battery }
        set { lock.lock(); battery = newValue; lock.unlock() }
    }

    func preventAutoLock() { device.preventAutoLock() }
    func allowAutoLock() { device.allowAutoLock() }
    func startBackgroundUsage(target: CLLocationManagerDelegate?) { device.startBackgroundUsage(target: target) }
    func stopBackgroundUsage() { device.stopBackgroundUsage() }
    func getBatteryLevel() -> Float? { batteryLevel }
    func getPseudoMacAddress() -> [UInt8] { mac }

    func vibrateAdvanced(f: Float, a: Float, d: Float) -> Bool {
        DispatchQueue.main.async {
            self.transport.send(.vibrate(frequency: f, amplitude: a, duration: d))
        }
        return true
    }

    func vibrate() {
        _ = vibrateAdvanced(f: 0.5, a: 1, d: 0.2)
    }

    //the iPhone's volume buttons and proximity sensor belong to its own session; the watch reads its own battery
    func registerVolButtonListener(target: NSObject) {}
    func unregisterVolButtonListener(target: NSObject) {}
    func startProximitySensor() {}
    func stopProximitySensor() {}
    func startBatteryLevelMonitoring() {}
    func stopBatteryLevelMonitoring() {}
}

//the motion readings of the watch's session on the iPhone: they arrive from the watch.
//Starting the readings (also when SlimeVR switches the magnetometer) tells the watch which mode to measure in
final class RelayedWatchMotion: MotionSource {
    let magnetometerCorrectionAvailable: Bool
    private let transport: RelayTransport
    private let lock = NSLock()
    private var sink: MotionSink?

    init(magnetometerAvailable: Bool, transport: RelayTransport) {
        self.magnetometerCorrectionAvailable = magnetometerAvailable
        self.transport = transport
    }

    func startUpdates(sink: MotionSink, useMagn: Bool) {
        lock.lock()
        self.sink = sink
        lock.unlock()
        DispatchQueue.main.async {
            self.transport.send(.magnetometer(useMagn))
        }
    }

    func stopUpdates() {
        lock.lock()
        sink = nil
        lock.unlock()
    }

    //readings from the watch, in the order it measured them
    func deliver(_ samples: [MotionSample]) {
        lock.lock()
        let sink = self.sink
        lock.unlock()
        guard let sink = sink else {
            return
        }
        for sample in samples {
            switch sample.kind {
            case .rotation: sink.provideRot(rot: sample.values)
            case .gyro: sink.provideGyro(gyro: sample.values)
            case .acceleration: sink.provideAccel(accel: sample.values)
            }
        }
    }
}
