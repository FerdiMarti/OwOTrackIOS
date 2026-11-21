//
//  OwOTrackWatchApp.swift
//  OwOTrack WatchOS
//

import SwiftUI
import Combine
import WatchKit

@main
struct OwOTrackWatchApp: App {
    //tracks through the iPhone app (RelayClient)
    @StateObject private var model: ConnectionModel
    private let haptics: StatusHaptics

    init() {
        let model = ConnectionModel()
        _model = StateObject(wrappedValue: model)
        haptics = StatusHaptics(model: model)
        WatchConnectivityTransport.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ConnectView(model: model)
        }
    }
}

//felt on the wrist: connected, connection lost, connecting failed. Follows the model, not the screen,
//so it also comes with the wrist down, when the screen isn't updated
final class StatusHaptics {
    private var subscription: AnyCancellable?

    init(model: ConnectionModel) {
        subscription = model.$status.removeDuplicates().dropFirst().sink { status in
            switch status {
            case .connected: WKInterfaceDevice.current().play(.success)
            case .reconnecting: WKInterfaceDevice.current().play(.retry)
            case .failed: WKInterfaceDevice.current().play(.failure)
            default: break
            }
        }
    }
}
