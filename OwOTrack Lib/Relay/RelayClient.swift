//
//  RelayClient.swift
//  OwOTrack
//
//  The watch side of the relay: watchOS doesn't let the watch app reach the server itself, so it streams its motion
//  readings to the iPhone app, which connects to the server for it (RelayHost) and reports back.
//

import Foundation

final class RelayClient: TrackingControl, ServerFinding, MotionSink {
    struct Timing {
        var batchInterval: TimeInterval = 0.05          //motion readings go to the iPhone in batches, 20 times a second
        var firstAnswerTimeout: TimeInterval = 15       //the iPhone app has to answer that soon after Connect (it may have to launch first)
        var iPhoneTimeout: TimeInterval = 10            //no sign of life from the iPhone for that long: the connection to it is lost
        var retryInterval: TimeInterval = 3             //how often the watch asks again meanwhile
        var giveUp: TimeInterval = 10 * 60              //like reconnecting to the server
        var batteryInterval: TimeInterval = 10
        var heartbeatInterval: TimeInterval = 5         //nothing else sent for that long: the watch tells the iPhone it's still there
        var confirmTimeout: TimeInterval = 1            //a batch the iPhone hasn't confirmed by then no longer holds up the next
        var statsInterval: TimeInterval = 60            //how often the log shows how fast the iPhone confirms the batches
    }

    //at most this many batches on their way: more would only queue up delay when the connection to the iPhone is slow
    private static let maxInFlight = 3

    private let transport: RelayTransport
    private let hardware: TrackerHardware
    private let motion: MotionSource
    private let logger: Logger
    private let timing: Timing

    //all on the main thread, except the readings collected for the next batch
    private var connectUI: ConnectUI?
    private var request: RelayStart?
    private var active = false
    private var magnetometer = true
    private var startedAt = Date()
    private var heardFromiPhone = false
    private var lastHeard = Date()
    private var lastAsked = Date()
    private var lostSince: Date?
    private var lastSent = Date()
    private var shownState: RelayStatus.State?
    private var shownServer = ServerType.unknown
    private var timers: [Timer] = []
    private var findCompletion: ((ServerSearchResult) -> Void)?    //the iPhone searches the network for the watch
    private var findTimer: Timer?
    private let batchLock = NSLock()
    private var batch: [MotionSample] = []
    private var sendsGyro = true                //SlimeVR doesn't use the gyro readings: a third less to send (guarded by batchLock)
    private var inFlight: [Int: Date] = [:]     //batches on their way, by number: when they were sent
    private var nextBatch = 0                   //never reset, so a late confirmation from an earlier session matches nothing
    private var roundTrips: TimeInterval = 0    //since statsStart: confirmed batches, their time there and back, unconfirmed ones
    private var confirmedBatches = 0
    private var unconfirmedBatches = 0
    private var statsStart = Date()

    init(transport: RelayTransport, hardware: TrackerHardware, motion: MotionSource, logger: Logger = Logger.getInstance(), timing: Timing = Timing()) {
        self.transport = transport
        self.hardware = hardware
        self.motion = motion
        self.logger = logger
        self.timing = timing
        transport.onReceive = { [weak self] data in
            self?.receive(data)
        }
    }

    // MARK: TrackingControl, on the main thread

    func start(ipAdress: String, port: String, magnetometer: Bool, connectUI: ConnectUI) {
        if active {
            return
        }
        self.connectUI = connectUI
        self.magnetometer = magnetometer
        active = true
        heardFromiPhone = false
        lostSince = nil
        shownState = nil
        shownServer = .unknown
        startedAt = Date()
        lastAsked = Date()
        connectUI.setLoading()
        batchLock.lock()
        sendsGyro = true
        batchLock.unlock()
        inFlight.removeAll()
        resetStats()
        logger.reset()
        logger.addEntry("Asking the iPhone to connect to \(ipAdress)")
        let request = RelayStart(address: ipAdress, port: port, magnetometer: magnetometer,
                                 mac: hardware.getPseudoMacAddress(), magnetometerAvailable: motion.magnetometerCorrectionAvailable)
        self.request = request
        hardware.preventAutoLock()
        hardware.startBackgroundUsage(target: nil)      //on the watch: the workout session, which keeps the app running with the wrist down
        hardware.startBatteryLevelMonitoring()
        motion.startUpdates(sink: self, useMagn: magnetometer)
        send(.start(request))                           //wakes the iPhone app if it isn't running
        sendBattery()
        timers = [
            Timer.scheduledTimer(withTimeInterval: timing.batchInterval, repeats: true) { [weak self] _ in self?.sendBatch() },
            Timer.scheduledTimer(withTimeInterval: timing.batteryInterval, repeats: true) { [weak self] _ in self?.sendBattery() },
            Timer.scheduledTimer(withTimeInterval: min(0.5, timing.retryInterval / 2), repeats: true) { [weak self] _ in self?.check() },
        ]
    }

    func stop() {
        if !active {
            return
        }
        if let request = request {
            send(.stop(session: request.session))
        }
        finish(failure: nil)
    }

    func sendReset(yaw: Bool) {
        if active {
            send(.reset(yaw: yaw))
        }
    }

    //the session ended: stopped here, ended by the iPhone, or the iPhone couldn't be reached
    private func finish(failure: String?) {
        if !active {
            return
        }
        active = false
        timers.forEach { $0.invalidate() }
        timers = []
        motion.stopUpdates()
        hardware.stopBatteryLevelMonitoring()
        hardware.stopBackgroundUsage()
        hardware.allowAutoLock()
        batchLock.lock()
        batch.removeAll()
        batchLock.unlock()
        if let failure = failure {
            logger.addEntry(failure)
            connectUI?.setFailed(failure)
        } else {
            connectUI?.setUnconnected()
        }
    }

    //the iPhone hasn't answered yet, or went quiet: ask again (which also wakes the iPhone app), and give up at some point
    private func check() {
        guard active, let request = request else {
            return
        }
        let now = Date()
        logStats(now)
        if !heardFromiPhone {
            if now.timeIntervalSince(startedAt) > timing.firstAnswerTimeout {
                send(.stop(session: request.session))       //in case the iPhone got the request after all: it doesn't connect for nothing
                finish(failure: "Open OwOTrack on your iPhone, then connect again")      //short enough for small watches
            } else if now.timeIntervalSince(lastAsked) > timing.retryInterval {
                lastAsked = now
                send(.start(request))
            }
            return
        }
        if now.timeIntervalSince(lastHeard) <= timing.iPhoneTimeout {
            //without motion readings (the simulator has no motion sensors) the iPhone would think the watch is gone
            if now.timeIntervalSince(lastSent) > timing.heartbeatInterval {
                send(.alive)
            }
            return
        }
        if lostSince == nil {
            lostSince = now
            shownState = .reconnecting
            logger.addEntry("Lost the connection to the iPhone")
            connectUI?.setReconnecting(until: now.addingTimeInterval(timing.giveUp))
        }
        if let lostSince = lostSince, now.timeIntervalSince(lostSince) > timing.giveUp {
            finish(failure: "Couldn't reach the iPhone for \(Int(timing.giveUp / 60)) minutes")
            return
        }
        if now.timeIntervalSince(lastAsked) > timing.retryInterval {
            lastAsked = now
            send(.start(request))
        }
    }

    private func send(_ message: RelayMessage) {
        transport.send(message)
        lastSent = Date()
    }

    // MARK: searching the network, through the iPhone

    //on the main thread
    func findServers(port: String, completion: @escaping (ServerSearchResult) -> Void) {
        findCompletion?(ServerSearchResult(failure: "Search again"))      //a newer search replaces it
        findCompletion = completion
        transport.send(.find(port: port, mac: hardware.getPseudoMacAddress()))     //wakes the iPhone app if it isn't running
        findTimer?.invalidate()
        findTimer = Timer.scheduledTimer(withTimeInterval: timing.firstAnswerTimeout + 3, repeats: false) { [weak self] _ in
            self?.finishFind(ServerSearchResult(failure: "Open OwOTrack on your iPhone, then search again"))
        }
    }

    private func finishFind(_ result: ServerSearchResult) {
        findTimer?.invalidate()
        findTimer = nil
        let completion = findCompletion
        findCompletion = nil
        completion?(result)
    }

    // MARK: from the iPhone, on the main thread

    private func receive(_ data: Data) {
        let packet = RelayPacket(data: data)
        if case .incompatible(let peerVersion)? = packet {
            //the iPhone app's version can't work with this one: say which app to update
            let hint = RelayPacket.updateHint(peerVersion: peerVersion, onWatch: true)
            finishFind(ServerSearchResult(failure: hint))
            finish(failure: hint)
            return
        }
        if case .message(.found(let result))? = packet {
            finishFind(result)
            return
        }
        guard active, case .message(let message)? = packet else {
            return
        }
        if case .status(let status) = message, status.session != request?.session {
            return      //about an earlier session: a late message, or the iPhone didn't get this session's request yet
        }
        heardFromiPhone = true
        lastHeard = Date()
        switch message {
        case .status(let status):
            show(status)
        case .log(let lines):
            lines.forEach { logger.addEntry($0) }
        case .vibrate(let frequency, let amplitude, let duration):
            if !hardware.vibrateAdvanced(f: frequency, a: amplitude, d: duration) {
                hardware.vibrate()
            }
        case .magnetometer(let use):
            if use != magnetometer {
                magnetometer = use
                request?.magnetometer = use         //if the iPhone starts the session over, it keeps SlimeVR's choice
                motion.stopUpdates()
                motion.startUpdates(sink: self, useMagn: use)
                connectUI?.setMagnometerToggle(use: use)
            }
        default:
            break
        }
    }

    //only changes go to the screen: the iPhone repeats its status every few seconds as a sign of life
    private func show(_ status: RelayStatus) {
        if lostSince != nil {
            lostSince = nil
            shownState = nil
            logger.addEntry("Connected to the iPhone again")
        }
        switch status.state {
        case .notConnected:
            if let reason = status.reason {
                logger.addEntry(reason)     //e.g. stopped on the iPhone
            }
            finish(failure: nil)
            return
        case .failed:
            finish(failure: status.reason ?? "Couldn't connect")
            return
        default:
            break
        }
        if status.serverType != shownServer {
            shownServer = status.serverType
            connectUI?.setServerType(status.serverType)
            batchLock.lock()
            sendsGyro = status.serverType != .slimeVR
            batchLock.unlock()
        }
        if status.state == shownState {
            return
        }
        shownState = status.state
        switch status.state {
        case .connected:
            connectUI?.setConnected()
        case .reconnecting:
            connectUI?.setReconnecting(until: status.giveUp ?? Date().addingTimeInterval(timing.giveUp))
        default:
            break       //connecting: the screen shows that since Connect was pressed
        }
    }

    private func sendBattery() {
        if let level = hardware.getBatteryLevel() {
            send(.battery(level))
        }
    }

    // MARK: MotionSink, from the sensor thread

    func provideRot(rot: [Data]) {
        add(.rotation, rot)
    }

    func provideGyro(gyro: [Data]) {
        add(.gyro, gyro)
    }

    func provideAccel(accel: [Data]) {
        add(.acceleration, accel)
    }

    private func add(_ kind: MotionSample.Kind, _ values: [Data]) {
        guard values.count == kind.count else {
            return
        }
        batchLock.lock()
        if kind == .gyro && !sendsGyro {
            batchLock.unlock()
            return
        }
        //only the newest reading of each kind: the server takes each reading as the current one, so the older ones of
        //a batch (they all arrive at once) would only be overwritten right away, or replayed late after a slow moment
        let sample = MotionSample(kind: kind, values: values)
        if let index = batch.firstIndex(where: { $0.kind == kind }) {
            batch[index] = sample
        } else {
            batch.append(sample)
        }
        batchLock.unlock()
    }

    //a few batches at a time: the next goes once the iPhone confirmed one, so a slow connection to the iPhone
    //means fewer batches instead of a growing queue and more and more delay. On the main thread
    private func sendBatch() {
        let now = Date()
        for (number, sentAt) in inFlight where now.timeIntervalSince(sentAt) > timing.confirmTimeout {
            inFlight[number] = nil
            unconfirmedBatches += 1
        }
        if inFlight.count >= RelayClient.maxInFlight {
            return
        }
        batchLock.lock()
        let samples = batch
        batch.removeAll()
        batchLock.unlock()
        if samples.isEmpty {
            return
        }
        let number = nextBatch
        nextBatch += 1
        let sent = transport.send(RelayPacket(samples: samples).data, onlyIfReachable: true, onConfirmed: { [weak self] confirmed in
            self?.confirm(number, confirmed)
        })
        if sent {
            inFlight[number] = now
            lastSent = now
        }
    }

    private func confirm(_ number: Int, _ confirmed: Bool) {
        guard let sentAt = inFlight.removeValue(forKey: number) else {
            return      //already counted as unconfirmed, or from an earlier session
        }
        if confirmed {
            roundTrips += Date().timeIntervalSince(sentAt)
            confirmedBatches += 1
        } else {
            unconfirmedBatches += 1
        }
    }

    //every so often: how fast the iPhone confirms, to see in the log what the connection to it manages
    private func logStats(_ now: Date) {
        guard now.timeIntervalSince(statsStart) >= timing.statsInterval else {
            return
        }
        if confirmedBatches > 0 || unconfirmedBatches > 0 {
            let average = confirmedBatches > 0 ? Int((roundTrips / Double(confirmedBatches) * 1000).rounded()) : 0
            logger.addEntry("To the iPhone: \(average) ms there and back, \(unconfirmedBatches) of \(confirmedBatches + unconfirmedBatches) messages unconfirmed")
        }
        resetStats()
    }

    private func resetStats() {
        roundTrips = 0
        confirmedBatches = 0
        unconfirmedBatches = 0
        statsStart = Date()
    }
}
