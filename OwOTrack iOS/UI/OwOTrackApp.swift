//
//  OwOTrackApp.swift
//  OwOTrack
//

import SwiftUI

@main
struct OwOTrackApp: App {
    //one model for the whole app, so the connection survives switching tabs
    @StateObject private var model = ConnectionModel()
    @StateObject private var dimmer = ScreenDimmer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView {
                    StatusView()
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Status", image: "status") }

                NavigationView {
                    ConnectView(model: model)
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Connect", image: "connect") }

                NavigationView {
                    InfoView()
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Information", image: "info") }
            }
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
