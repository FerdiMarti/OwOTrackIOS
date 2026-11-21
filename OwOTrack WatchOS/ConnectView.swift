//
//  ConnectView.swift
//  OwOTrack WatchOS
//
//  The watch app, in three pages: tracking (status, Connect, resets), settings (server, magnetometer)
//  and details (permissions, iPhone, battery, log). The watch tracks through the iPhone app (RelayClient).
//

import SwiftUI
import Combine
import WatchKit
import HealthKit

struct ConnectView: View {
    @ObservedObject var model: ConnectionModel

    var body: some View {
        TabView {
            TrackingPage(model: model)
            SettingsPage(model: model)
            DetailsPage(model: model)
        }
        .pagedVertically()
        .onChange(of: model.status) { status in
            vibrate(for: status)
        }
        .confirmationDialog("Several servers answered", isPresented: choosingServer, titleVisibility: .visible) {
            ForEach(model.serverChoices) { server in
                Button([server.address, server.type.name].compactMap { $0 }.joined(separator: " · ")) {
                    model.chooseServer(server)
                }
            }
        }
    }

    //several servers answered the search: pick one
    private var choosingServer: Binding<Bool> {
        Binding(get: { !model.serverChoices.isEmpty }, set: { shown in
            if !shown {
                model.chooseServer(nil)
            }
        })
    }

    //felt on the wrist: connected, connection lost, connecting failed
    private func vibrate(for status: ConnectionModel.Status) {
        switch status {
        case .connected: WKInterfaceDevice.current().play(.success)
        case .reconnecting: WKInterfaceDevice.current().play(.retry)
        case .failed: WKInterfaceDevice.current().play(.failure)
        default: break
        }
    }
}

// MARK: tracking

private struct TrackingPage: View {
    @ObservedObject var model: ConnectionModel
    @Environment(\.isLuminanceReduced) private var wristDown     //always-on display: only the status
    //the spinner and the symbols sit in the same box, one title line high, so they're centered on the title's
    //first line in every state (also when a failure message wraps)
    private let lineHeight = UIFont.preferredFont(forTextStyle: .headline).lineHeight

    var body: some View {
        //the buttons at the bottom; if a long failure message doesn't leave room for that (small watches),
        //the page scrolls instead of cutting the message short
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                indicator
                    .frame(width: lineHeight, height: lineHeight)
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)      //all its lines
            }
            detail
                .font(.footnote)
                .foregroundColor(.secondary)
            if !wristDown {
                Spacer(minLength: 4)
                Button {
                    model.connectPressed()
                } label: {
                    Text(model.canDisconnect ? "Disconnect" : "Connect")
                        .frame(maxWidth: .infinity)
                }
                .tint(model.canDisconnect ? .red : .green)
                .disabled(model.isConnecting || model.isSearching)
                if case .failed = model.status, model.offersSearch {
                    SearchButton(model: model, thenConnect: true)       //the server may have a new address
                }
                if model.isConnected && model.serverType == .slimeVR {
                    HStack(spacing: 6) {
                        Button("Yaw reset") {
                            model.requestReset(yaw: true)
                        }
                        .doubleTapPresses()
                        Button("Full reset") {
                            model.requestReset(yaw: false)
                        }
                    }
                    .font(.footnote)
                }
            }
        }
        .scenePadding(.horizontal)      //the watch's standard side margins, which its buttons keep anyway
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var indicator: some View {
        if model.isConnecting || model.isReconnecting || model.isSearching {
            ProgressView()
                .scaleEffect(0.85)      //the watch's spinner is bigger than a symbol
        } else {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundColor(color)
        }
    }

    private var title: String {
        switch model.status {
        case .notConnected: return "Not connected"
        case .searching: return "Searching for SlimeVR…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .failed(let reason), .error(let reason): return reason
        }
    }

    private var color: Color {
        switch model.status {
        case .notConnected: return .secondary
        case .searching, .connecting: return .primary
        case .connected: return .green
        case .reconnecting: return .orange
        case .failed, .error: return .red
        }
    }

    private var symbol: String {
        switch model.status {
        case .connected: return "checkmark.circle.fill"
        case .failed, .error: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.status {
        case .notConnected:
            Text("Tracks through your iPhone")
        case .searching:
            Text("Your iPhone searches its Wi-Fi")
        case .connecting:
            Text("\(model.ip) · via iPhone")
        case .connected:
            Text("\(model.serverType.name ?? model.ip) · via iPhone")
        case .reconnecting:
            if let deadline = model.reconnectDeadline {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text("Gives up in \(timeLeft(until: deadline, now: context.date))")
                        .monospacedDigit()
                }
            }
        case .failed, .error:
            EmptyView()     //the message says it all; small watches need the room (the log is on the last page)
        }
    }

    private func timeLeft(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: settings

private struct SettingsPage: View {
    @ObservedObject var model: ConnectionModel
    @State private var showsMagnetometerInfo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server")
                    .font(.headline)
                TextField("Automatic", text: $model.ip)        //empty: Connect searches the network
                    .disabled(!model.canEdit)
                TextField("Port", text: $model.port)
                    .disabled(!model.canEdit)
                SearchButton(model: model, thenConnect: false)
                if !model.recentServers.isEmpty {
                    Text("Recent")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    ForEach(model.recentServers) { server in
                        Button(server.port == "6969" ? server.address : "\(server.address):\(server.port)") {
                            model.useRecentServer(server)
                        }
                        .font(.footnote)
                        .disabled(!model.canEdit)
                    }
                }
                Toggle(isOn: $model.useMagnetometer) {
                    Text("Magnetometer")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)        //not broken in two on small watches
                }
                .disabled(!model.canEdit)
                Button {
                    showsMagnetometerInfo = true
                } label: {
                    Label("About the magnetometer", systemImage: "info.circle")
                }
                .font(.footnote)
            }
            .scenePadding(.horizontal)
        }
        .sheet(isPresented: $showsMagnetometerInfo) {
            InfoText(title: "Magnetometer", paragraphs: [
                "Turning it off can improve latency and battery life, and avoids problems near magnets. The tracker drifts more around the vertical axis then.",
                "With SlimeVR, SlimeVR controls it and this switch follows. Allow it in SlimeVR's settings and in the tracker's settings.",
            ])
        }
    }
}

// MARK: details

private struct DetailsPage: View {
    @ObservedObject var model: ConnectionModel
    @State private var health = HKAuthorizationStatus.notDetermined
    @State private var iPhoneReachable = false
    @State private var battery: Float?
    private let refresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                stateRow(symbol: "heart.fill", title: "Health", good: health == .sharingAuthorized, bad: health == .sharingDenied, text: healthText)
                stateRow(symbol: "iphone", title: "iPhone", good: iPhoneReachable, bad: false,
                         text: iPhoneReachable ? "Reachable" : "Not reachable right now. Keep it close and OwOTrack open on it")
                if let battery = battery {
                    Label("Battery \(Int((battery * 100).rounded())) %", systemImage: "battery.75")
                        .font(.footnote)
                }
                Text("Log")
                    .font(.headline)
                Text(model.log.isEmpty ? "Nothing logged yet" : model.log)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("OwOTrack \(version)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .scenePadding(.horizontal)
        }
        .onAppear(perform: update)
        .onReceive(refresh) { _ in update() }
    }

    private var healthText: String {
        switch health {
        case .sharingAuthorized:
            return "Allowed: tracking keeps running when the screen turns off"
        case .sharingDenied:
            return "Not allowed: tracking stops when the screen turns off. Allow it on your iPhone: Settings → Privacy & Security → Health → OwOTrack"
        default:
            return "Not asked yet: the watch asks when you connect. It keeps tracking running when the screen turns off"
        }
    }

    private func stateRow(symbol: String, title: String, good: Bool, bad: Bool, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: good ? "checkmark.circle.fill" : (bad ? "xmark.circle.fill" : "exclamationmark.circle.fill"))
                    .foregroundColor(good ? .green : (bad ? .red : .yellow))
            }
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func update() {
        health = HKHealthStore.isHealthDataAvailable() ? HKHealthStore().authorizationStatus(for: HKObjectType.workoutType()) : .notDetermined
        iPhoneReachable = WatchConnectivityTransport.shared.isReachable
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let level = WKInterfaceDevice.current().batteryLevel
        battery = level < 0 ? nil : level
    }
}

//searches the iPhone's Wi-Fi for SlimeVR: fills in the address, or also connects (after a failed connection)
private struct SearchButton: View {
    @ObservedObject var model: ConnectionModel
    let thenConnect: Bool

    var body: some View {
        Button {
            model.searchPressed(thenConnect: thenConnect)
        } label: {
            Label(model.isSearching ? "Searching…" : "Search network", systemImage: "antenna.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .disabled(!model.canEdit)
    }
}

//an explanation, opened from an "About" button
private struct InfoText: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.footnote)
                }
            }
        }
    }
}

private extension View {
    //pages scroll vertically from watchOS 10 on, like Apple's apps
    @ViewBuilder
    func pagedVertically() -> some View {
        if #available(watchOS 10.0, *) {
            self.tabViewStyle(.verticalPage)
        } else {
            self.tabViewStyle(.page)
        }
    }

    //the double-tap gesture (watchOS 11, newer watches) presses this button
    @ViewBuilder
    func doubleTapPresses() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
