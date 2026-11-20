//
//  Recorders.swift
//  OwOTrackTests
//

import Foundation
@testable import OwOTrack_iOS

//a connection that doesn't use the network: it keeps everything the app sends, so a test can check the bytes.
//nothing ever arrives through it; tests hand server data to the client's processReceivedData directly
final class RecordingConnection: CompatibleUDPClient {
    private let lock = NSLock()
    private var sentData: [Data] = []

    var sent: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sentData
    }

    var packets: [SentPacket] {
        return sent.compactMap { SentPacket($0) }
    }

    func clear() {
        lock.lock()
        sentData.removeAll()
        lock.unlock()
    }

    func open(cb: @escaping () -> Void, onProblem: @escaping (String, Bool) -> Void) {
        cb()
    }

    func close() {}

    func sendUDP(_ content: Data) {
        lock.lock()
        sentData.append(content)
        lock.unlock()
    }

    func receiveUDP(cb: @escaping (Data?) -> Void) {}
}

//the connect screen as the tests see it: every status the app reports, in order
final class RecordingUI: ConnectUI {
    private let lock = NSLock()
    private var recordedStates: [String] = []
    private var recordedToggles: [Bool] = []

    var states: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStates
    }

    var lastState: String? {
        return states.last
    }

    var magnetometerToggles: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedToggles
    }

    private func record(_ state: String) {
        lock.lock()
        recordedStates.append(state)
        lock.unlock()
    }

    func setLoading() { record("connecting") }
    func setConnected() { record("connected") }
    func setUnconnected() { record("not connected") }
    func setReconnecting() { record("reconnecting") }

    func setMagnometerToggle(use: Bool) {
        lock.lock()
        recordedToggles.append(use)
        lock.unlock()
    }

    func updateLogs(text: String) {}
}
