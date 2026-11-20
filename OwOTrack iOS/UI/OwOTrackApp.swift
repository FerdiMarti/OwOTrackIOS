//
//  OwOTrackApp.swift
//  OwOTrack
//

import SwiftUI

@main
struct OwOTrackApp: App {
    @StateObject private var model = ConnectionModel()
    @StateObject private var dimmer = ScreenDimmer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView(model: model, dimmer: dimmer)
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
                //the screen dims only while connected and while the app is in the foreground
                .onChange(of: model.isConnected) { _ in updateDimmer() }
                .onChange(of: scenePhase) { _ in updateDimmer() }
        }
    }

    private func updateDimmer() {
        dimmer.setActive(model.isConnected && scenePhase == .active)
    }
}
