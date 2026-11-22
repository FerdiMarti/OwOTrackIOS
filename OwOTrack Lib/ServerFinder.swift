//
//  ServerFinder.swift
//  OwOTrack
//
//  Finds SlimeVR (or the old owoTrack driver) on the local network: the app's handshake goes to every address of the
//  Wi-Fi network, and the server answers it like for any tracker. Sent to each address on its own, so it needs no
//  broadcast permission, only Local Network access like connecting. SlimeVR's own announcements aren't used: it only
//  sends them while no tracker is connected.
//

import Foundation
import Darwin

//a server that answered the search
struct FoundServer: Codable, Equatable, Identifiable {
    let address: String
    let type: ServerType

    var id: String {
        return address
    }
}

//what a search found, or why it couldn't search
struct ServerSearchResult: Codable, Equatable {
    var servers: [FoundServer] = []
    var failure: String?
}

protocol ServerFinding: AnyObject {
    //searches for a few seconds; the completion is called once, on any thread
    func findServers(port: String, completion: @escaping (ServerSearchResult) -> Void)
}

final class LocalServerFinder: ServerFinding {
    struct Timing {
        var slimeVRResend: TimeInterval = 0.3   //the handshake again to the addresses that didn't answer (lost packets)
        var driverAfter: TimeInterval = 0.8     //then the short handshake the old owoTrack driver reads, to those that still didn't
        var driverResend: TimeInterval = 1.3
        var total: TimeInterval = 2
    }

    //networks bigger than this are searched around this device's own address only
    static let maxAddresses = 1022

    private let mac: [UInt8]
    private let platform: String
    private let candidates: () -> [String]?
    private let timing: Timing
    private let queue = DispatchQueue(label: "LocalServerFinder")

    //mac and platform: the handshake of the tracker that will connect (SlimeVR keeps it as that tracker, no extra entry).
    //candidates: the addresses to ask, nil without a local network
    init(mac: [UInt8], platform: String, candidates: @escaping () -> [String]? = LocalServerFinder.networkAddresses, timing: Timing = Timing()) {
        self.mac = mac
        self.platform = platform
        self.candidates = candidates
        self.timing = timing
    }

    func findServers(port: String, completion: @escaping (ServerSearchResult) -> Void) {
        queue.async {
            completion(self.search(port: port))
        }
    }

    private func search(port: String) -> ServerSearchResult {
        guard let portNumber = UInt16(port) else {
            return ServerSearchResult(failure: "Please enter a valid port number")
        }
        guard let hosts = candidates(), !hosts.isEmpty else {
            return ServerSearchResult(failure: "Connect to Wi-Fi to search for SlimeVR")
        }
        let socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketHandle >= 0 else {
            return ServerSearchResult(failure: "Couldn't search the network")
        }
        defer { close(socketHandle) }
        _ = fcntl(socketHandle, F_SETFL, fcntl(socketHandle, F_GETFL, 0) | O_NONBLOCK)

        let addresses: [(host: String, address: sockaddr_in)] = hosts.compactMap { host in
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = portNumber.bigEndian
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
                return nil
            }
            return (host, address)
        }
        let slimeVR = UDPGyroProviderClient.handshakePacket(slime: true, mac: mac, platform: platform)
        let driver = UDPGyroProviderClient.handshakePacket(slime: false, mac: mac, platform: platform)
        var steps: [(at: TimeInterval, packet: Data, isDriver: Bool)] = [
            (0, slimeVR, false), (timing.slimeVRResend, slimeVR, false),
            (timing.driverAfter, driver, true), (timing.driverResend, driver, true),
        ]

        var types: [String: ServerType] = [:]
        var order: [String] = []
        var driverSent = false
        var anySent = false

        //the answers waiting now, or arriving within the time. Before the short handshake went out, an answer is to the
        //full one: SlimeVR. After, only to the short one: the old driver, which can't read the full one
        func collectAnswers(waiting time: TimeInterval) {
            let until = Date().addingTimeInterval(time)
            repeat {
                var pollHandle = pollfd(fd: socketHandle, events: Int16(POLLIN), revents: 0)
                let wait = until.timeIntervalSinceNow
                if poll(&pollHandle, 1, Int32(max(0, min(50, wait * 1000)))) > 0 {
                    while let host = receiveAnswer(on: socketHandle) {
                        if types[host] == nil {
                            types[host] = driverSent ? .owoTrackDriver : .slimeVR
                            order.append(host)
                        }
                    }
                }
            } while until.timeIntervalSinceNow > 0
        }

        let start = Date()
        while true {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= timing.total {
                break
            }
            while let step = steps.first, step.at <= elapsed {
                steps.removeFirst()
                if step.isDriver && !driverSent {
                    //first the answers already here, so a slow moment (many addresses, a busy device) can't make
                    //SlimeVR's answers count as answers to the short handshake. SlimeVR then gets no short handshake,
                    //which it would show as another tracker
                    collectAnswers(waiting: 0.1)
                }
                driverSent = driverSent || step.isDriver
                for (host, address) in addresses where types[host] == nil {
                    anySent = send(step.packet, to: address, on: socketHandle) || anySent
                }
            }
            //answers until the next step
            let next = min(steps.first?.at ?? timing.total, timing.total)
            collectAnswers(waiting: max(0.001, next - Date().timeIntervalSince(start)))
        }
        //not a single handshake went out: iOS blocks the local network (not allowed, or still asking on the first search)
        if !anySent && order.isEmpty && !addresses.isEmpty {
            return ServerSearchResult(failure: platform == "watchOS" ? "Allow Local Network access on your iPhone, then search again"
                                                                     : "Allow Local Network access for OwOTrack, then search again")
        }
        return ServerSearchResult(servers: order.compactMap { host in types[host].map { FoundServer(address: host, type: $0) } })
    }

    //true if it went out
    @discardableResult
    private func send(_ packet: Data, to address: sockaddr_in, on socketHandle: Int32) -> Bool {
        var address = address
        for _ in 0..<5 {
            let sent = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(socketHandle, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            //a full send buffer: wait a moment and try again. Other errors (no such host, no local network access): skip the address
            if sent >= 0 {
                return true
            }
            if errno != ENOBUFS && errno != EAGAIN {
                return false
            }
            usleep(2000)
        }
        return false
    }

    //the address of the next handshake answer waiting (other packets are skipped), nil when none is waiting
    private func receiveAnswer(on socketHandle: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 128)
        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketHandle, &buffer, buffer.count, 0, $0, &length)
                }
            }
            if count <= 0 {
                return nil
            }
            //byte 3 and "Hey OVR =D", from SlimeVR and the old driver alike
            if LocalServerFinder.isHandshakeAnswer(buffer.prefix(count)) {
                return LocalServerFinder.format(UInt32(bigEndian: from.sin_addr.s_addr))
            }
        }
    }

    static func isHandshakeAnswer<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
        return bytes.first == 3 && bytes.dropFirst().starts(with: Array("Hey OVR =D".utf8))
    }

    // MARK: the network's addresses

    //the addresses of the local networks this device is on: Wi-Fi (or Ethernet) and its own hotspot, not cellular or VPN.
    //Its own address first: SlimeVR can run on the same computer (the app on a Mac, or in the simulator).
    //nil when it isn't on such a network
    static func networkAddresses() -> [String]? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else {
            return nil
        }
        defer { freeifaddrs(list) }
        var hosts: [UInt32] = []
        var onNetwork = false
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            let flags = Int32(interface.ifa_flags)
            let name = String(cString: interface.ifa_name)
            guard let address = interface.ifa_addr, let mask = interface.ifa_netmask,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  name.hasPrefix("en") || name.hasPrefix("bridge") else {
                continue
            }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard isPrivate(ip) else {
                continue
            }
            onNetwork = true
            hosts += [ip] + otherAddresses(ip: ip, mask: netmask)
        }
        var seen = Set<UInt32>()
        return onNetwork ? hosts.filter { seen.insert($0).inserted }.map(format) : nil
    }

    //the network's addresses without its own, the network's and the broadcast address.
    //Networks bigger than a /22 (1022 addresses): only the /22 around its own address
    static func otherAddresses(ip: UInt32, mask: UInt32) -> [UInt32] {
        let mask = max(mask, 0xFFFF_FC00)
        let network = ip & mask
        let broadcast = network | ~mask
        guard broadcast > network &+ 1 else {
            return []
        }
        return ((network + 1)..<broadcast).filter { $0 != ip }
    }

    //home and office networks: 10.x, 172.16–31.x, 192.168.x
    static func isPrivate(_ ip: UInt32) -> Bool {
        return ip & 0xFF00_0000 == 0x0A00_0000 || ip & 0xFFF0_0000 == 0xAC10_0000 || ip & 0xFFFF_0000 == 0xC0A8_0000
    }

    static func format(_ ip: UInt32) -> String {
        return "\(ip >> 24).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }

    static func parse(_ address: String) -> UInt32? {
        var value = in_addr()
        guard inet_pton(AF_INET, address, &value) == 1 else {
            return nil
        }
        return UInt32(bigEndian: value.s_addr)
    }
}
