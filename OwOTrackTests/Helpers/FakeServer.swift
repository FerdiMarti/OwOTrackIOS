//
//  FakeServer.swift
//  OwOTrackTests
//

import Foundation
import Darwin
@testable import OwOTrack_iOS

//a UDP server on 127.0.0.1 for the connection tests. It acts like SlimeVR v21.1.0 or like the old owoTrack driver,
//and can be up, silent (packets vanish, like a Wi-Fi drop) or closed (like quitting the server app: the system answers "port unreachable")
final class FakeServer {
    enum Mode {
        //answers the handshake with 64 bytes, acknowledges the sensor description. Its packets are big-endian with
        //packet number 0 (SlimeVR doesn't count its own), and it pings the tracker twice a second
        case slimeVR
        //can't read handshakes over 28 bytes, never acknowledges the sensor description, doesn't ping.
        //Its packets are little-endian (its computer's byte order) without a packet number
        case oldDriver
    }

    enum State {
        case up, silent, closed
    }

    struct Received {
        let time: Date
        let packet: SentPacket
        let raw: Data
        let sourcePort: UInt16
    }

    let mode: Mode
    let port: UInt16
    var heartbeatInterval: TimeInterval = 0.5
    var pingInterval: TimeInterval = 0.5

    private let lock = NSLock()
    private var wantedState = State.up
    private var receivedPackets: [Received] = []
    private var outbox: [Data] = []
    private var rawOutbox: [Data] = []
    private var sentPings: [UInt32] = []
    private var running = true
    private let finished = DispatchSemaphore(value: 0)

    init(mode: Mode) {
        self.mode = mode
        let socket = FakeServer.openSocket(port: 0)
        port = FakeServer.boundPort(socket)
        let thread = Thread { [unowned self] in self.run(socket: socket) }
        thread.name = "FakeServer"
        thread.start()
    }

    func setState(_ state: State) {
        lock.lock()
        wantedState = state
        lock.unlock()
    }

    //sends a packet the way SlimeVR does (type, packet number 0, payload) to the client that last sent a handshake
    func send(type: UInt32, payload: [UInt8]) {
        lock.lock()
        outbox.append(Data(bytes(type)) + payload)     //the packet number is added when it's sent
        lock.unlock()
    }

    //sends bytes as they are (e.g. the old driver's packets, which have no packet number) to the client
    func sendRaw(_ data: Data) {
        lock.lock()
        rawOutbox.append(data)
        lock.unlock()
    }

    var received: [Received] {
        lock.lock()
        defer { lock.unlock() }
        return receivedPackets
    }

    func received(type: UInt32, after time: Date = .distantPast) -> [Received] {
        return received.filter { $0.packet.type == type && $0.time > time }
    }

    //SlimeVR's pings (packet 10 with an id) the client sent back, as SlimeVR measures the latency with them
    var answeredPings: Int {
        lock.lock()
        let ids = sentPings.map { bytes($0) }
        lock.unlock()
        return received(type: 10).filter { ids.contains($0.packet.payload) }.count
    }

    var lastHandshake: SlimeVRHandshake? {
        return received(type: 3).last.flatMap { SlimeVRHandshake(packet: $0.raw) }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        finished.wait()
    }

    // MARK: server thread

    private func run(socket initialSocket: Int32) {
        var socket = initialSocket
        var state = State.up
        var client: sockaddr_in?
        var nextHeartbeat = Date()
        var nextPing = Date()
        var buffer = [UInt8](repeating: 0, count: 2048)

        func sendToClient(_ typeAndPayload: Data) {
            guard var address = client else { return }
            let data = Data(typeAndPayload.prefix(4)) + Data(bytes(Int64(0))) + typeAndPayload.dropFirst(4)
            FakeServer.send(data, from: socket, to: &address)
        }

        while true {
            lock.lock()
            let keepRunning = running
            let wanted = wantedState
            let queued = state == .up && client != nil ? outbox : []
            if !queued.isEmpty { outbox.removeAll() }
            let queuedRaw = state == .up && client != nil ? rawOutbox : []
            if !queuedRaw.isEmpty { rawOutbox.removeAll() }
            lock.unlock()
            if !keepRunning { break }

            if wanted != state {
                if wanted == .closed {
                    Darwin.close(socket)
                    socket = -1
                } else if state == .closed {
                    socket = FakeServer.openSocket(port: port)
                }
                state = wanted
            }
            if state == .closed {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            for packet in queued {
                sendToClient(packet)
            }
            if var address = client {
                for raw in queuedRaw {
                    FakeServer.send(raw, from: socket, to: &address)
                }
            }
            if state == .up, var address = client, Date() >= nextHeartbeat {
                if mode == .slimeVR {
                    sendToClient(Data(bytes(UInt32(1))))
                } else {
                    FakeServer.send(driverPacket(type: 1), from: socket, to: &address)
                }
                nextHeartbeat = Date().addingTimeInterval(heartbeatInterval)
            }
            if mode == .slimeVR && state == .up && client != nil && Date() >= nextPing {
                let id = UInt32.random(in: 1...UInt32.max)
                lock.lock()
                sentPings.append(id)
                lock.unlock()
                sendToClient(Data(bytes(UInt32(10)) + bytes(id)))
                nextPing = Date().addingTimeInterval(pingInterval)
            }

            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(socket, &buffer, buffer.count, 0, $0, &length) }
            }
            if count <= 0 {
                continue    //timeout (20 ms), so state changes and heartbeats are handled promptly
            }
            let data = Data(buffer[0..<count])
            guard let packet = SentPacket(data) else { continue }
            lock.lock()
            receivedPackets.append(Received(time: Date(), packet: packet, raw: data, sourcePort: UInt16(bigEndian: from.sin_port)))
            lock.unlock()
            if state != .up { continue }

            switch packet.type {
            case 3:
                if mode == .oldDriver && data.count > 28 {
                    continue    //the old driver's receive buffer is too small for SlimeVR's handshake
                }
                client = from
                var reply = Data(mode == .slimeVR ? slimeVRHandshakeReply : driverHandshakeReply)
                FakeServer.sendRaw(&reply, from: socket, to: &from)
            case 15 where mode == .slimeVR:
                sendToClient(Data(bytes(UInt32(15)) + [packet.payload.first ?? 0, 1]))     //acknowledged: sensor id, status ok
            default:
                break
            }
        }
        if socket >= 0 {
            Darwin.close(socket)
        }
        finished.signal()
    }

    private static func openSocket(port: UInt16) -> Int32 {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        var yes: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 20_000)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(result == 0, "FakeServer couldn't bind port \(port)")
        return socket
    }

    private static func boundPort(_ socket: Int32) -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func send(_ data: Data, from socket: Int32, to address: inout sockaddr_in) {
        var copy = data
        sendRaw(&copy, from: socket, to: &address)
    }

    private static func sendRaw(_ data: inout Data, from socket: Int32, to address: inout sockaddr_in) {
        let count = data.count
        _ = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socket, buffer.baseAddress, count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
