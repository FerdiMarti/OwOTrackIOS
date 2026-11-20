//
//  ConnectView.swift
//  OwOTrack WatchOS
//

import SwiftUI

//the watch app's only screen: server address, magnetometer switch, connect button and the connection log
struct ConnectView: View {
    @StateObject private var model = ConnectionModel()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(statusColor)
                        .id("top")
                    //right below the status, so it's visible without scrolling
                    Button(model.canDisconnect ? "Disconnect" : "Connect") {
                        model.connectPressed()
                    }
                    .disabled(model.isConnecting)
                    if model.isConnecting || model.isReconnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    TextField("IP Address", text: $model.ip)
                        .disabled(!model.canEdit)
                    TextField("Port", text: $model.port)
                        .disabled(!model.canEdit)
                    Toggle("Magnetometer", isOn: $model.useMagnetometer)
                        .disabled(!model.canEdit)
                    Text(model.log)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .id("log")
                }
            }
            //while connecting, follow the newest log line (the progress, or why it failed)
            .onChange(of: model.log) { _ in
                if model.isConnecting {
                    proxy.scrollTo("log", anchor: .bottom)
                }
            }
            //once connected, go back up to the status and the Disconnect button
            .onChange(of: model.isConnected) { connected in
                if connected {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
    }

    private var statusText: String {
        switch model.status {
        case .notConnected: return "Not Connected"
        case .connecting: return "Loading..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .notConnected: return .gray
        case .connecting: return .primary
        case .connected: return .green
        case .reconnecting: return .orange
        case .error: return .red
        }
    }
}
