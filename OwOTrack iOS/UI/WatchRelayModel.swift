//
//  WatchRelayModel.swift
//  OwOTrack
//

import Foundation
import Combine

//the relay for the Apple Watch, for the iPhone's screen. The watch starts tracking, and this iPhone connects to the server
//for it, as a tracker of its own. Created when the app starts, also when the watch launches it in the background
final class WatchRelayModel: ObservableObject {
    static let shared = WatchRelayModel()

    @Published private(set) var status = RelayStatus(state: .notConnected)
    @Published private(set) var watchAvailable = false      //a paired watch with the watch app

    private let transport = WatchConnectivityTransport.shared
    private let host: RelayHost

    private init() {
        host = RelayHost(transport: transport, device: StaticHardware(IPhoneHardware.self))
        host.onStatusChange = { [weak self] status in
            self?.status = status
        }
        transport.onStateChange = { [weak self] in
            self?.refresh()
        }
        transport.activate()
        refresh()
    }

    var isActive: Bool {
        return status.isActive
    }

    //ends the watch's connection from the iPhone
    func stop() {
        host.stop(tellWatch: true)
    }

    private func refresh() {
        watchAvailable = transport.watchAppAvailable
    }
}
