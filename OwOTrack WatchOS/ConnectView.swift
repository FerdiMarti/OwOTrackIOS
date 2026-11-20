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
                    TextField("IP Address", text: $model.ip)
                        .disabled(!model.canEdit)
                    TextField("Port", text: $model.port)
                        .disabled(!model.canEdit)
                    Toggle("Magnetometer", isOn: $model.useMagnetometer)
                        .disabled(!model.canEdit)
                    Button(model.isConnected ? "Disconnect" : "Connect") {
                        model.connectPressed()
                    }
                    .disabled(model.isConnecting)
                    if model.isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    Text(model.log)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .id("log")
                }
            }
            //keep the newest log line visible
            .onChange(of: model.log) { _ in
                proxy.scrollTo("log", anchor: .bottom)
            }
        }
    }

    private var statusText: String {
        switch model.status {
        case .notConnected: return "Not Connected"
        case .connecting: return "Loading..."
        case .connected: return "Connected"
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .notConnected: return .gray
        case .connecting: return .primary
        case .connected: return .green
        case .error: return .red
        }
    }
}
