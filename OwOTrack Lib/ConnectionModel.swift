//
//  ConnectionModel.swift
//  OwOTrack
//

import Foundation
import Combine

let RECENT_SERVERS_USERDEFAULTS_KEY = "recentServers"

//a server the app connected to, offered again on the connect screen
struct RecentServer: Equatable, Identifiable {
    let address: String
    let port: String

    var id: String {
        return "\(address):\(port)"
    }
}

//State and actions of the connect screen, for the SwiftUI views of the iPhone and watch apps.
//TrackingService and Logger report changes through ConnectUI from background threads, so every change moves to the main thread.
final class ConnectionModel: ObservableObject, ConnectUI {

    enum Status: Equatable {
        case notConnected
        case connecting
        case connected
        case reconnecting       //the connection was lost, the app keeps trying until it's back or the user disconnects
        case failed(String)     //connecting failed or reconnecting gave up, with the reason
        case error(String)      //the address or port isn't valid
    }

    static let maxRecentServers = 5

    @Published var ip: String
    @Published var port: String
    @Published var useMagnetometer: Bool
    @Published private(set) var status: Status = .notConnected
    @Published private(set) var log = ""
    @Published private(set) var serverType = ServerType.unknown
    @Published private(set) var localNetwork = LocalNetworkAccess.unknown
    @Published private(set) var reconnectDeadline: Date?        //while reconnecting: when the app gives up
    @Published private(set) var recentServers: [RecentServer]

    private let service = TrackingService()

    init() {
        let defaults = UserDefaults.standard
        ip = defaults.string(forKey: IP_USERDEFAULTS_KEY) ?? "192.168.0.10"
        port = defaults.string(forKey: PORT_USERDEFAULTS_KEY) ?? "6969"
        useMagnetometer = defaults.object(forKey: MAGNETOMETER_USERDEFAULTS_KEY) as? Bool ?? true
        let saved = defaults.array(forKey: RECENT_SERVERS_USERDEFAULTS_KEY) as? [[String: String]] ?? []
        recentServers = saved.compactMap { entry in
            guard let address = entry["address"], let port = entry["port"] else { return nil }
            return RecentServer(address: address, port: port)
        }
        Logger.getInstance().attachUI(connectUI: self)
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = status { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = status { return true }
        return false
    }

    //while connected or reconnecting, the button disconnects
    var canDisconnect: Bool {
        return isConnected || isReconnecting
    }

    //address and magnetometer can only be changed while not connected
    var canEdit: Bool {
        return !isConnected && !isConnecting && !isReconnecting
    }

    //connects, or disconnects if connected or reconnecting
    func connectPressed() {
        if canDisconnect {
            service.stop()
            return
        }
        if isConnecting {
            return
        }
        if !ConnectionModel.isValidPort(port) {
            status = .error("Please enter a valid port number")
            return
        }
        let address = ip.trimmingCharacters(in: .whitespaces)
        if !ConnectionModel.isValidAddress(address) {
            status = .error("Please enter a valid IP address or computer name")
            return
        }
        ip = address
        service.start(ipAdress: address, port: port, magnetometer: useMagnetometer, connectUI: self)
    }

    //fills in a server connected to before
    func useRecentServer(_ server: RecentServer) {
        if !canEdit {
            return
        }
        ip = server.address
        port = server.port
    }

    //the connected server goes first; the list keeps the last few, without duplicates
    private func rememberServer() {
        let server = RecentServer(address: ip, port: port)
        recentServers = Array(([server] + recentServers.filter { $0 != server }).prefix(ConnectionModel.maxRecentServers))
        let saved = recentServers.map { ["address": $0.address, "port": $0.port] }
        UserDefaults.standard.set(saved, forKey: RECENT_SERVERS_USERDEFAULTS_KEY)
    }

    // MARK: ConnectUI, called from any thread

    func setLoading() {
        onMain {
            self.status = .connecting
            self.log = ""
            self.serverType = .unknown
            self.reconnectDeadline = nil
        }
    }

    func setConnected() {
        onMain {
            self.status = .connected
            self.reconnectDeadline = nil
            self.rememberServer()
        }
    }

    func setUnconnected() {
        onMain {
            self.status = .notConnected
            self.serverType = .unknown
            self.reconnectDeadline = nil
        }
    }

    //keeps the server type: it's the same server the app tries to reach again
    func setReconnecting(until giveUp: Date) {
        onMain {
            self.status = .reconnecting
            self.reconnectDeadline = giveUp
        }
    }

    func setFailed(_ reason: String) {
        onMain {
            self.status = .failed(reason)
            self.serverType = .unknown
            self.reconnectDeadline = nil
        }
    }

    func setServerType(_ type: ServerType) {
        onMain { self.serverType = type }
    }

    func setLocalNetworkAccess(_ access: LocalNetworkAccess) {
        onMain { self.localNetwork = access }
    }

    //used if server triggers a change in magnetometer use
    func setMagnometerToggle(use: Bool) {
        onMain { self.useMagnetometer = use }
    }

    func updateLogs(text: String) {
        onMain { self.log = text }
    }

    private func onMain(_ change: @escaping () -> Void) {
        DispatchQueue.main.async(execute: change)
    }

    // MARK: Validation

    static func isValidPort(_ port: String) -> Bool {
        guard let nr = Int(port) else {
            return false
        }
        return nr >= 0 && nr <= 65535
    }

    //the server's address: an IPv4 address like 192.168.1.20, or a computer name like DESKTOP-AB12CD.local
    static func isValidAddress(_ address: String) -> Bool {
        return isValidIPAddress(address) || isValidComputerName(address)
    }

    static func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 4 {
            return false
        }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(isDigit), let nr = Int(part) else {
                return false
            }
            return nr <= 255
        }
    }

    //a host name: labels of letters, digits and hyphens separated by dots, a label not starting or ending with a hyphen.
    //only digits and dots is a mistyped IP address (e.g. 192.168.1), not a name
    static func isValidComputerName(_ name: String) -> Bool {
        if name.isEmpty || name.count > 253 || name.allSatisfy({ isDigit($0) || $0 == "." }) {
            return false
        }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            return (1...63).contains(label.count)
                && label.first != "-" && label.last != "-"
                && label.allSatisfy { ($0.isASCII && $0.isLetter) || isDigit($0) || $0 == "-" }
        }
    }

    private static func isDigit(_ c: Character) -> Bool {
        return ("0"..."9").contains(c)
    }
}
