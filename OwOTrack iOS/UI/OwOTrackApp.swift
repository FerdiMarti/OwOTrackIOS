//
//  OwOTrackApp.swift
//  OwOTrack
//

import SwiftUI

@main
struct OwOTrackApp: App {
    //one model for the whole app, so the connection survives switching tabs
    @StateObject private var model = ConnectionModel()

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
        }
    }
}
