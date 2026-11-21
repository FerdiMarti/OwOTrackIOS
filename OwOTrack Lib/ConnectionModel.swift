//
//  ConnectionModel.swift
//  OwOTrack
//

import Foundation
import Combine

let RECENT_SERVERS_USERDEFAULTS_KEY = "recentServers"
let PAIRED_RECENT_SERVERS_USERDEFAULTS_KEY = "recentServersOfPairedDevice"     //the watch's on the iPhone, the iPhone's on the watch

//a server the app connected to, offered again on the connect screen
struct RecentServer: Equatable, Identifiable {
    let address: String
    let port: String
    var used = Date.distantPast         //when it was last connected to

    var id: String {
        return "\(address):\(port)"
    }

    //as saved, and as sent to the paired device
    var plist: [String: Any] {
        return ["address": address, "port": port, "used": used.timeIntervalSince1970]
    }

    //lists saved before entries had a date keep their order: the first is the newest
    static func list(fromPlist entries: [[String: Any]]) -> [RecentServer] {
        return entries.enumerated().compactMap { index, entry in
            guard let address = entry["address"] as? String, let port = entry["port"] as? String else {
                return nil
            }
            let used = (entry["used"] as? Double).map { Date(timeIntervalSince1970: $0) }
                ?? Date(timeIntervalSince1970: Double(entries.count - index))
            return RecentServer(address: address, port: port, used: used)
        }
    }

    static func load(key: String) -> [RecentServer] {
        return list(fromPlist: UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? [])
    }

    static func save(_ servers: [RecentServer], key: String) {
        UserDefaults.standard.set(servers.map(\.plist), forKey: key)
    }
}

//the iPhone and the watch show each other's recent servers: each sends its own list, the latest one arrives
//even when the other app isn't running
protocol RecentServerSharing: AnyObject {
    //this device's own servers, newest first
    func shareRecentServers(_ servers: [RecentServer])
    //the paired device's own servers arrived. On the main thread
    var onPairedRecentServers: (([RecentServer]) -> Void)? { get set }
}

//State and actions of the connect screen, for the SwiftUI views of the iPhone and watch apps.
//TrackingService and Logger report changes through ConnectUI from background threads, so every change moves to the main thread.
final class ConnectionModel: ObservableObject, ConnectUI {

    enum Status: Equatable {
        case notConnected
        case searching          //looking for the server on the network
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
    @Published private(set) var recentServers: [RecentServer]     //this device's and the paired device's
    @Published private(set) var serverChoices: [FoundServer] = []   //several servers answered the search: the user picks one
    @Published private(set) var offersSearch = false                //connecting failed: searching may find the server's new address

    private let service: TrackingControl
    private let finder: ServerFinding
    private var connectAfterChoice = false
    private let sharing: RecentServerSharing?
    private var ownServers: [RecentServer]
    private var pairedServers: [RecentServer]

    //this device's tracking; on the watch, the relay through the iPhone
    static func makeService() -> TrackingControl {
        #if os(watchOS)
        return RelayClient(transport: WatchConnectivityTransport.shared, hardware: StaticHardware(WatchHardware.self), motion: GyroHandler.getInstance())
        #else
        return TrackingService()
        #endif
    }

    //the recent servers go to the paired iPhone or watch, and come from it
    static func makeSharing() -> RecentServerSharing? {
        #if canImport(WatchConnectivity)
        return WatchConnectivityTransport.shared
        #else
        return nil
        #endif
    }

    //searches the network: the iPhone itself; for the watch, the iPhone does (RelayClient)
    static func makeFinder(for service: TrackingControl) -> ServerFinding {
        if let finder = service as? ServerFinding {
            return finder
        }
        return LocalServerFinder(mac: StaticHardware(TrackingService.deviceHardware).getPseudoMacAddress(), platform: "iOS")
    }

    init(service: TrackingControl = ConnectionModel.makeService(), sharing: RecentServerSharing? = ConnectionModel.makeSharing(),
         finder: ServerFinding? = nil) {
        self.service = service
        self.finder = finder ?? ConnectionModel.makeFinder(for: service)
        self.sharing = sharing
        let defaults = UserDefaults.standard
        ip = defaults.string(forKey: IP_USERDEFAULTS_KEY) ?? ""         //empty: Connect searches the network for the server
        port = defaults.string(forKey: PORT_USERDEFAULTS_KEY) ?? "6969"
        useMagnetometer = defaults.object(forKey: MAGNETOMETER_USERDEFAULTS_KEY) as? Bool ?? true
        ownServers = RecentServer.load(key: RECENT_SERVERS_USERDEFAULTS_KEY)
        pairedServers = RecentServer.load(key: PAIRED_RECENT_SERVERS_USERDEFAULTS_KEY)
        recentServers = ConnectionModel.merged(ownServers, pairedServers)
        Logger.getInstance().attachUI(connectUI: self)
        sharing?.onPairedRecentServers = { [weak self] servers in
            self?.pairedServersArrived(servers)
        }
        sharing?.shareRecentServers(ownServers)
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

    var isSearching: Bool {
        return status == .searching
    }

    //while connected or reconnecting, the button disconnects
    var canDisconnect: Bool {
        return isConnected || isReconnecting
    }

    //address and magnetometer can only be changed while not connected
    var canEdit: Bool {
        return !isConnected && !isConnecting && !isReconnecting && !isSearching
    }

    //connects, or disconnects if connected or reconnecting. Without an address, it searches the network first
    func connectPressed() {
        if canDisconnect {
            service.stop()
            return
        }
        if isConnecting || isSearching {
            return
        }
        if !ConnectionModel.isValidPort(port) {
            status = .error("Please enter a valid port number")
            return
        }
        let address = ip.trimmingCharacters(in: .whitespaces)
        if address.isEmpty {
            search(thenConnect: true)
            return
        }
        if !ConnectionModel.isValidAddress(address) {
            status = .error("Please enter a valid IP address or computer name")
            return
        }
        ip = address
        service.start(ipAdress: address, port: port, magnetometer: useMagnetometer, connectUI: self)
    }

    //the search button fills in the server it finds; "Search network" after a failed connection also connects to it
    func searchPressed(thenConnect: Bool = false) {
        if !canEdit {
            return
        }
        if !ConnectionModel.isValidPort(port) {
            status = .error("Please enter a valid port number")
            return
        }
        search(thenConnect: thenConnect)
    }

    //the user picked one of the servers that answered (nil: none)
    func chooseServer(_ server: FoundServer?) {
        let connect = connectAfterChoice
        serverChoices = []
        connectAfterChoice = false
        if let server = server {
            use(server, connect: connect)
        }
    }

    private func search(thenConnect: Bool) {
        status = .searching
        offersSearch = false
        serverChoices = []
        finder.findServers(port: port) { [weak self] result in
            DispatchQueue.main.async {
                self?.searchFinished(result, thenConnect: thenConnect)
            }
        }
    }

    private func searchFinished(_ result: ServerSearchResult, thenConnect: Bool) {
        guard isSearching else {
            return
        }
        if let failure = result.failure {
            status = .failed(failure)
            return
        }
        switch result.servers.count {
        case 0:
            #if os(watchOS)
            status = .failed("No SlimeVR server found on your iPhone's Wi-Fi")
            #else
            status = .failed("No SlimeVR server found on this Wi-Fi")
            #endif
        case 1:
            status = .notConnected
            use(result.servers[0], connect: thenConnect)
        default:
            status = .notConnected
            connectAfterChoice = thenConnect
            serverChoices = result.servers
        }
    }

    private func use(_ server: FoundServer, connect: Bool) {
        ip = server.address
        if connect {
            service.start(ipAdress: server.address, port: port, magnetometer: useMagnetometer, connectUI: self)
        }
    }

    //a yaw reset (else a full reset) in SlimeVR, while connected
    func requestReset(yaw: Bool) {
        if isConnected {
            service.sendReset(yaw: yaw)
        }
    }

    //fills in a server connected to before
    func useRecentServer(_ server: RecentServer) {
        if !canEdit {
            return
        }
        ip = server.address
        port = server.port
    }

    //the connected server goes first; the list keeps the last few, without duplicates.
    //It's also filled in on the next start (on the watch nothing else saves it: the iPhone connects for it)
    private func rememberServer() {
        let defaults = UserDefaults.standard
        defaults.set(ip, forKey: IP_USERDEFAULTS_KEY)
        defaults.set(port, forKey: PORT_USERDEFAULTS_KEY)
        defaults.set(useMagnetometer, forKey: MAGNETOMETER_USERDEFAULTS_KEY)
        let server = RecentServer(address: ip, port: port, used: Date())
        ownServers = Array(([server] + ownServers.filter { $0.id != server.id }).prefix(ConnectionModel.maxRecentServers))
        RecentServer.save(ownServers, key: RECENT_SERVERS_USERDEFAULTS_KEY)
        recentServers = ConnectionModel.merged(ownServers, pairedServers)
        sharing?.shareRecentServers(ownServers)     //only its own: the paired device's don't go back to it
    }

    private func pairedServersArrived(_ servers: [RecentServer]) {
        pairedServers = Array(servers.prefix(ConnectionModel.maxRecentServers))
        RecentServer.save(pairedServers, key: PAIRED_RECENT_SERVERS_USERDEFAULTS_KEY)
        recentServers = ConnectionModel.merged(ownServers, pairedServers)
    }

    //both devices' servers, newest first, each once, at most maxRecentServers
    static func merged(_ own: [RecentServer], _ paired: [RecentServer]) -> [RecentServer] {
        var seen = Set<String>()
        let newestFirst = (own + paired).sorted { $0.used > $1.used }
        return Array(newestFirst.filter { seen.insert($0.id).inserted }.prefix(maxRecentServers))
    }

    // MARK: ConnectUI, called from any thread

    func setLoading() {
        onMain {
            self.status = .connecting
            self.offersSearch = false
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
            self.offersSearch = false
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
            self.offersSearch = true        //the server may have a new address
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
