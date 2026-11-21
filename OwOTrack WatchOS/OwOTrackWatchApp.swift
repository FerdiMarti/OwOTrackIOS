//
//  OwOTrackWatchApp.swift
//  OwOTrack WatchOS
//

import SwiftUI

@main
struct OwOTrackWatchApp: App {
    //tracks through the iPhone app (RelayClient)
    @StateObject private var model = ConnectionModel()

    init() {
        WatchConnectivityTransport.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ConnectView(model: model)
        }
    }
}
