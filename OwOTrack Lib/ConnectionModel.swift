//
//  ConnectionModel.swift
//  OwOTrack
//

import Foundation
import Combine

//State and actions of the connect screen, for SwiftUI views (the watch app now, the iPhone app later).
//TrackingService and Logger report changes through ConnectUI from background threads, so every change moves to the main thread.
final class ConnectionModel: ObservableObject, ConnectUI {

    enum Status {
        case notConnected
        case connecting
        case connected
        case error(String)
    }

    @Published var ip: String
    @Published var port: String
    @Published var useMagnetometer: Bool
    @Published private(set) var status: Status = .notConnected
    @Published private(set) var log = ""

    private let service = TrackingService()
    private let discoverer = AutoDiscovery()

    init() {
        let defaults = UserDefaults.standard
        ip = defaults.string(forKey: IP_USERDEFAULTS_KEY) ?? "192.168.0.10"
        port = defaults.string(forKey: PORT_USERDEFAULTS_KEY) ?? "6969"
        useMagnetometer = defaults.object(forKey: MAGNETOMETER_USERDEFAULTS_KEY) as? Bool ?? true
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

    //address and magnetometer can only be changed while not connected
    var canEdit: Bool {
        return !isConnected && !isConnecting
    }

    //connects, or disconnects if already connected
    func connectPressed() {
        if isConnected {
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
        if !ConnectionModel.isValidIPAddress(ip) {
            status = .error("Please enter a valid ip address")
            return
        }
        service.start(ipAdress: ip, port: port, magnetometer: useMagnetometer, connectUI: self)
    }

    //looks for a running owoTrack driver on the network and fills in its address (doesn't work with SlimeVR)
    func discoverPressed() {
        if !canEdit {
            return
        }
        status = .connecting
        log = ""
        discoverer.sendDiscovery(cb: { error, ip, port in
            self.onMain {
                if !error {
                    self.ip = ip
                    self.port = port
                }
                self.status = .notConnected
            }
        })
    }

    // MARK: ConnectUI, called from any thread

    func setLoading() {
        onMain {
            self.status = .connecting
            self.log = ""
        }
    }

    func setConnected() {
        onMain { self.status = .connected }
    }

    func setUnconnected() {
        onMain { self.status = .notConnected }
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

    static func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 4 {
            return false
        }
        return parts.allSatisfy { part in
            guard let nr = Int(part) else {
                return false
            }
            return nr >= 0 && nr <= 255
        }
    }
}
