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
    @Published private(set) var lastWorkout: WorkoutSummary?  //the watch's last session saved to Health

    private static let lastWorkoutKey = "lastWatchWorkout"
    private let transport = WatchConnectivityTransport.shared
    private let host: RelayHost

    private init() {
        host = RelayHost(transport: transport, device: StaticHardware(IPhoneHardware.self))
        host.onStatusChange = { [weak self] status in
            self?.status = status
        }
        host.onWorkout = { [weak self] summary in
            self?.lastWorkout = summary
            UserDefaults.standard.set(try? JSONEncoder().encode(summary), forKey: WatchRelayModel.lastWorkoutKey)
        }
        lastWorkout = UserDefaults.standard.data(forKey: WatchRelayModel.lastWorkoutKey)
            .flatMap { try? JSONDecoder().decode(WorkoutSummary.self, from: $0) }
        #if DEBUG
        if ConnectionModel.screenshotAction == "summary" {     //App Store screenshots
            lastWorkout = WorkoutSummary(start: Date().addingTimeInterval(-50 * 60), duration: 45 * 60 + 12)
        }
        #endif
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
