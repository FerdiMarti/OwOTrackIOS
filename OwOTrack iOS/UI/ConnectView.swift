//
//  ConnectView.swift
//  OwOTrack
//

import SwiftUI

//server address, magnetometer switch, Connect button and the connection log
struct ConnectView: View {
    @ObservedObject var model: ConnectionModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if model.isConnecting {
                    ProgressView()
                }
                Text(statusText)
                    .foregroundColor(statusColor)
            }
            .frame(maxWidth: .infinity, minHeight: 21)
            .padding(.top, 40)
            addressField("IP Address", text: $model.ip)
            addressField("Port", text: $model.port)
            Toggle("Use Magnetometer", isOn: $model.useMagnetometer)
                .disabled(!model.canEdit)
            Button(model.isConnected ? "Disconnect" : "Connect") {
                model.connectPressed()
            }
            .frame(maxWidth: .infinity)
            .disabled(model.isConnecting)
            LogView(text: model.log, placeholder: "Logs")
        }
        .padding(.horizontal, 20)
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    //pressing return closes the keyboard
    private func addressField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 14))
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .disabled(!model.canEdit)
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
