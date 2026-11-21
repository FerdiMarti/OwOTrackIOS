//
//  OwOTrackApp.swift
//  OwOTrack
//

import SwiftUI

@main
struct OwOTrackApp: App {
    @StateObject private var model = ConnectionModel()
    @StateObject private var dimmer = ScreenDimmer()
    //created right away, so the relay also answers a watch that launches the app in the background
    @StateObject private var watchRelay = WatchRelayModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView(model: model, dimmer: dimmer, watchRelay: watchRelay)
                //while dimmed, the touch that brightens the screen ends here instead of pressing something
                .overlay(alignment: .center) {
                    if dimmer.isDimmed {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in dimmer.touched() })
                            .ignoresSafeArea()
                            .accessibilityLabel("Screen dimmed. Touch to brighten")
                    }
                }
                //the screen dims only while tracking or reconnecting (this iPhone, or the watch through it) and while the app is in the foreground
                .onChange(of: model.canDisconnect) { _ in updateDimmer() }
                .onChange(of: watchRelay.isActive) { _ in updateDimmer() }
                .onChange(of: scenePhase) { _ in updateDimmer() }
        }
    }

    init() {
        _ = WatchRelayModel.shared
    }

    private func updateDimmer() {
        dimmer.setActive((model.canDisconnect || watchRelay.isActive) && scenePhase == .active)
    }
}
