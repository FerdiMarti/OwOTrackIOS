//
//  MainView.swift
//  OwOTrack
//
//  The app's only screen: connection status, server address, magnetometer, Connect button,
//  sensors, permissions and the connection log. Explanations open from the ⓘ buttons.
//

import SwiftUI

//the privacy policy linked at the bottom of the screen (the same as in App Store Connect)
let PRIVACY_POLICY_URL = URL(string: "https://owotrack.martiniapps.dev")

struct MainView: View {
    @ObservedObject var model: ConnectionModel
    @ObservedObject var dimmer: ScreenDimmer
    @ObservedObject var watchRelay: WatchRelayModel
    @StateObject private var location = LocationPermission()
    @State private var sheet: Sheet?
    @State private var selectedSensor: Sensor?
    @Environment(\.dynamicTypeSize) private var typeSize
    //room for the status in every state (up to three lines: reconnecting, or a failure message that wraps),
    //so the controls below don't move when the status text changes
    @ScaledMetric(relativeTo: .subheadline) private var statusHeight: CGFloat = 88

    private let sensors = GyroHandler.getInstance()
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad

    enum Sheet: Identifiable {
        case info(InfoTopic)
        case log

        var id: String {
            switch self {
            case .info(let topic): return topic.id
            case .log: return "log"
            }
        }
    }

    var body: some View {
        GeometryReader { screen in
            ScrollView {
                //the connection controls at the top, the overview at the bottom, room in between.
                //When everything doesn't fit (large text, keyboard), the screen scrolls instead
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("OwOTrack")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        status
                            .frame(minHeight: statusHeight, alignment: .topLeading)
                        //the address, magnetometer and port belong to the button that connects with them
                        VStack(alignment: .leading, spacing: 16) {
                            settings
                            connectButton
                        }
                        if showsVolumeButtons && volumeButtonPositions == nil {
                            volumeButtonLegend
                        }
                    }
                    Spacer(minLength: 32)
                    VStack(alignment: .leading, spacing: 20) {
                        sensorRow
                        permissionRow
                        if watchRelay.watchAvailable || watchRelay.isActive {
                            watchRow
                        }
                        if model.isConnected || watchRelay.isActive {
                            screenRow
                        }
                        logRow
                        footer
                    }
                }
                .padding(.horizontal, 32)   //leaves a gap to the volume button labels at the left edge
                .padding(.vertical, 12)
                .frame(maxWidth: 560)       //a readable width on iPad
                //fills the screen so the overview sits at the bottom; on a big iPad screen only up to a height
                //where the two parts still belong together
                .frame(minHeight: isPad ? min(screen.size.height, 820) : screen.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .bounceOnlyWhenScrollable()
        }
        .overlay(alignment: .topLeading) {
            if showsVolumeButtons, let positions = volumeButtonPositions {
                VolumeButtonLabels(positions: positions) { sheet = .info(.volumeButtons) }
            }
        }
        .overlay(alignment: .bottom) {
            dimmingBanner
        }
        .confirmationDialog("Several servers answered", isPresented: choosingServer, titleVisibility: .visible) {
            ForEach(model.serverChoices) { server in
                Button([server.address, server.type.name].compactMap { $0 }.joined(separator: " · ")) {
                    model.chooseServer(server)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .info(let topic):
                InfoSheet(topic: topic, model: model, location: location)
            case .log:
                LogSheet(model: model)
            }
        }
        .onChange(of: model.status) { status in
            vibrate(for: status)
            //VoiceOver says what changed, wherever its focus is
            UIAccessibility.post(notification: .announcement, argument: status.title)
        }
    }

    //the volume buttons only do something with SlimeVR (resets), and only if they aren't switched off
    private var showsVolumeButtons: Bool {
        return model.isConnected && model.serverType == .slimeVR && model.useVolumeButtons
    }

    //where the labels next to the volume buttons go. nil where the buttons aren't on the side of the screen
    //(iPad, iPhone Duo): there, a line of text explains them instead
    private var volumeButtonPositions: VolumeButtonPositions? {
        return isPad ? nil : VolumeButtonPositions.current
    }

    // MARK: status

    private var status: some View {
        //the spinner and the symbols sit in the same box, one title line high, so they're centered on the
        //title's first line in every state (also when a failure message wraps to two lines)
        let lineHeight = UIFont.preferredFont(forTextStyle: .title2).lineHeight
        return HStack(alignment: .top, spacing: 10) {
            Group {
                if model.isConnecting || model.isReconnecting || model.isSearching {
                    ProgressView()
                } else {
                    Image(systemName: statusSymbol)
                        .foregroundColor(statusColor)
                        .font(.title2)
                }
            }
            .frame(width: lineHeight, height: lineHeight)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                statusDetail
                    .font(.subheadline)
            }
        }
    }

    private var statusTitle: String {
        return model.status.title
    }

    private var statusColor: Color {
        switch model.status {
        case .notConnected: return .secondary
        case .searching, .connecting: return .primary
        case .connected: return .green
        case .reconnecting: return .orange
        case .failed, .error: return .red
        }
    }

    private var statusSymbol: String {
        switch model.status {
        case .connected: return "checkmark.circle.fill"
        case .failed, .error: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch model.status {
        case .notConnected:
            Text(model.ip.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Connect finds SlimeVR on your Wi-Fi, or enter the computer's address."
                 : "Enter the address of the computer running SlimeVR, then connect.")
                .foregroundColor(.secondary)
        case .searching:
            Text("On your Wi-Fi network")
                .foregroundColor(.secondary)
        case .connecting:
            Text(model.ip)
                .foregroundColor(.secondary)
        case .connected:
            serverLine
        case .reconnecting:
            serverLine
            if let deadline = model.reconnectDeadline {
                HStack(spacing: 6) {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text("Gives up in \(timeLeft(until: deadline, now: context.date))")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    InfoButton(subject: "reconnecting") { sheet = .info(.reconnecting) }
                }
            }
        case .failed:
            HStack(spacing: 16) {
                if model.offersSearch {
                    Button {
                        model.searchPressed(thenConnect: true)
                    } label: {
                        Label("Search network", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                Button {
                    sheet = .info(.cantConnect)
                } label: {
                    Label("Can't connect?", systemImage: "questionmark.circle")
                }
            }
            .buttonStyle(.borderless)
        case .error:
            EmptyView()
        }
    }

    //"SlimeVR · my-pc.local", with an explanation of the server
    private var serverLine: some View {
        HStack(spacing: 6) {
            Text([model.serverType.name, model.ip].compactMap { $0 }.joined(separator: " · "))
                .foregroundColor(.secondary)
            if model.serverType != .unknown {
                InfoButton(subject: model.serverType.name ?? "the server") { sheet = .info(.server(model.serverType)) }
            }
        }
    }

    private func timeLeft(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TextField("Automatic", text: $model.ip)       //empty: Connect searches the network
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .disabled(!model.canEdit)
                    .accessibilityLabel("Server address")
                if !model.recentServers.isEmpty {
                    Menu {
                        ForEach(model.recentServers) { server in
                            Button(server.port == "6969" ? server.address : "\(server.address):\(server.port)") {
                                model.useRecentServer(server)
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.large)
                            .minimumTapArea()
                    }
                    .disabled(!model.canEdit)
                    .accessibilityLabel("Recent servers")
                }
                Button {
                    model.searchPressed()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .imageScale(.large)
                        .minimumTapArea()
                }
                .disabled(!model.canEdit)
                .accessibilityLabel("Search the network for SlimeVR")
                InfoButton(subject: "the server address") { sheet = .info(.address) }
            }
            HStack(spacing: 12) {
                Toggle("Magnetometer", isOn: $model.useMagnetometer)
                    .disabled(!model.canEdit)
                InfoButton(subject: "the magnetometer") { sheet = .info(.magnetometer) }
            }
            DisclosureGroup("Advanced") {
                HStack(spacing: 12) {
                    Text("Port")
                    TextField("6969", text: $model.port)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .frame(maxWidth: 110)
                        .disabled(!model.canEdit)
                        .accessibilityLabel("Port")
                    Spacer()
                    InfoButton(subject: "the port") { sheet = .info(.port) }
                }
                .padding(.top, 8)
                HStack(spacing: 12) {
                    Toggle("Volume buttons reset", isOn: $model.useVolumeButtons)     //can be switched while tracking
                    InfoButton(subject: "the volume buttons") { sheet = .info(.volumeButtons) }
                }
            }
        }
    }

    private var connectButton: some View {
        Button {
            model.connectPressed()
        } label: {
            Text(model.canDisconnect ? "Disconnect" : "Connect")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(model.canDisconnect ? .red : .accentColor)
        .disabled(model.isConnecting || model.isSearching)
    }

    //several servers answered the search: pick one
    private var choosingServer: Binding<Bool> {
        Binding(get: { !model.serverChoices.isEmpty }, set: { shown in
            if !shown {
                model.chooseServer(nil)
            }
        })
    }

    //where the volume buttons aren't on the side (iPad, iPhone Duo): a legend instead of labels at the edge
    private var volumeButtonLegend: some View {
        HStack(spacing: 12) {
            Label("Volume + yaw reset, volume − full reset", systemImage: "speaker.wave.2")
                .font(.subheadline)
            Spacer()
            InfoButton(subject: "the volume buttons") { sheet = .info(.volumeButtons) }
        }
    }

    // MARK: sensors and permissions

    //a title with its badges in one row; with very large text, the badges go below the title
    @ViewBuilder
    private func badgeRow<Badges: View>(_ title: String, @ViewBuilder badges: () -> Badges) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                HStack(spacing: 16) {
                    badges()
                }
            }
        } else {
            HStack(spacing: 16) {
                Text(title)
                    .font(.headline)
                Spacer()
                badges()
            }
        }
    }

    private var sensorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            badgeRow("Sensors") {
                ForEach(Sensor.allCases) { sensor in
                    let available = sensor.isAvailable(sensors)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedSensor = selectedSensor == sensor ? nil : sensor
                        }
                    } label: {
                        Badge(symbol: sensor.symbol,
                              stateSymbol: available ? "checkmark.circle.fill" : "xmark.circle.fill",
                              stateColor: available ? .green : .red,
                              selected: selectedSensor == sensor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(sensor.name), \(available ? "available" : "not available")")
                    .accessibilityHint("Shows what the sensor is for")
                }
            }
            if let sensor = selectedSensor {
                Text("**\(sensor.name)**: \(sensor.isAvailable(sensors) ? "available" : "not available on this device"). \(sensor.purpose)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionRow: some View {
        badgeRow("Permissions") {
            permissionBadge("Location", symbol: "location.fill", state: location.state, topic: .location)
            permissionBadge("Local Network", symbol: "wifi", state: PermissionState.localNetwork(model.localNetwork), topic: .localNetwork)
        }
    }

    private func permissionBadge(_ name: String, symbol: String, state: PermissionState, topic: InfoTopic) -> some View {
        Button {
            sheet = .info(topic)
        } label: {
            Badge(symbol: symbol, stateSymbol: state.symbol, stateColor: state.color, selected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) permission, \(state.spokenName)")
        .accessibilityHint("Explains the permission and how to change it")
    }

    // MARK: Apple Watch

    //the watch tracks through this iPhone: its state, and a button to end it from here
    private var watchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title3)
                .foregroundColor(watchColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Watch")
                    .font(.headline)
                Text(watchDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if watchRelay.isActive {
                Button("Stop") {
                    watchRelay.stop()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            InfoButton(subject: "the Apple Watch") { sheet = .info(.watch) }
        }
        .accessibilityElement(children: .contain)
    }

    private var watchDetail: String {
        let status = watchRelay.status
        switch status.state {
        case .notConnected:
            if let workout = watchRelay.lastWorkout {
                return "Last session saved to Health: \(workout.durationText)"
            }
            return "Connect on the watch to track with it"
        case .connecting: return "Connecting…"
        case .connected: return ["Tracking through this iPhone", status.serverType.name].compactMap { $0 }.joined(separator: " · ")
        case .reconnecting: return "Reconnecting…"
        case .failed: return status.reason ?? "Couldn't connect"
        }
    }

    private var watchColor: Color {
        switch watchRelay.status.state {
        case .connected: return .green
        case .connecting: return .primary
        case .reconnecting: return .orange
        case .failed: return .red
        case .notConnected: return .secondary
        }
    }

    // MARK: screen, log and footer

    private var screenRow: some View {
        HStack(spacing: 12) {
            Label("Screen dims after 30 s", systemImage: "moon")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            InfoButton(subject: "the screen") { sheet = .info(.screen) }
        }
    }

    private var logRow: some View {
        let lastLine = model.log.split(separator: "\n").last.map(String.init)
        return Button {
            sheet = .log
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                Text(lastLine ?? "Connection log")
                    .lineLimit(1)
                    .foregroundColor(lastLine == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
            .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Connection log")
        .accessibilityValue(lastLine ?? "empty")
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return VStack(spacing: 6) {
            Text("OwOTrack \(version) (\(build))")
            if let url = PRIVACY_POLICY_URL {
                Link("Privacy Policy", destination: url)
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
    }

    //"Dimming in 5…" before the screen dims, "Touch to brighten" while it's dimmed
    @ViewBuilder
    private var dimmingBanner: some View {
        if let seconds = dimmer.countdown {
            banner("Dimming in \(seconds)…", symbol: "moon")
        } else if dimmer.isDimmed {
            banner("Touch to brighten", symbol: "sun.max")
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .monospacedDigit()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
            .accessibilityAddTraits(.updatesFrequently)
    }

    //felt on the body: connected, connection lost, connecting failed
    private func vibrate(for status: ConnectionModel.Status) {
        let generator = UINotificationFeedbackGenerator()
        switch status {
        case .connected: generator.notificationOccurred(.success)
        case .reconnecting: generator.notificationOccurred(.warning)
        case .failed: generator.notificationOccurred(.error)
        default: break
        }
    }
}

extension View {
    //Apple's minimum of 44 × 44 pt to tap: a small icon or line also reacts to taps right around it,
    //without taking more room on the screen
    func minimumTapArea() -> some View {
        background(Color.clear.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()))
    }

    //the screen fills the display, so it only needs to scroll when the content is taller (large text, keyboard,
    //small screens). Without this, iOS lets it bounce even when everything fits. Needs iOS 16.4; before, it keeps bouncing
    @ViewBuilder
    func bounceOnlyWhenScrollable() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

//an icon with a small state symbol on its corner, for sensors and permissions
private struct Badge: View {
    let symbol: String
    let stateSymbol: String
    let stateColor: Color
    let selected: Bool
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 34     //grows with the text size, like the symbols

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(selected ? .accentColor : .primary)
                .frame(width: size, height: size * 0.9)
            Image(systemName: stateSymbol)
                .font(.caption)
                .foregroundColor(stateColor)
                .background(Circle().fill(Color(.systemBackground)))
                .offset(x: size * 0.09, y: size * 0.09)
        }
        .contentShape(Rectangle())
        .minimumTapArea()
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)     //four badges still fit next to each other
    }
}

enum Sensor: CaseIterable, Identifiable {
    case motion, accelerometer, gyroscope, magnetometer

    var id: Self { self }

    var name: String {
        switch self {
        case .motion: return "Motion processing"
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .magnetometer: return "Magnetometer"
        }
    }

    var symbol: String {
        switch self {
        case .motion: return "move.3d"
        case .accelerometer: return "speedometer"
        case .gyroscope: return "gyroscope"
        case .magnetometer: return "location.north.circle"
        }
    }

    var purpose: String {
        switch self {
        case .motion: return "Combines the sensors into the iPhone's orientation, which the app sends to the server. Tracking needs it."
        case .accelerometer: return "Measures movement. Part of the orientation, and sent to the server."
        case .gyroscope: return "Measures how fast the iPhone turns. Part of the orientation."
        case .magnetometer: return "A compass. While the magnetometer switch is on, it corrects slow turning around the vertical axis (yaw drift)."
        }
    }

    func isAvailable(_ sensors: GyroHandler) -> Bool {
        switch self {
        case .motion: return sensors.motionAvailable
        case .accelerometer: return sensors.accelerometerAvailable
        case .gyroscope: return sensors.gyroAvailable
        case .magnetometer: return sensors.magnetometerAvailable
        }
    }
}

//slim tabs at the left screen edge, next to the volume buttons, inside the content's margin so they don't cover anything.
//The buttons sit at different heights on different iPhones, so the positions come from a table per model
private struct VolumeButtonLabels: View {
    let positions: VolumeButtonPositions
    let onTap: () -> Void
    private let width: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            //up to 80 pt long, shorter where the buttons are close together (e.g. iPhone SE), so the tabs don't overlap
            let length = min(80, (positions.down - positions.up) * geometry.size.height - 6)
            label(sign: "+", action: "Yaw reset", spoken: "Volume up", length: length)
                .position(x: width / 2, y: geometry.size.height * positions.up)
            label(sign: "−", action: "Full reset", spoken: "Volume down", length: length)
                .position(x: width / 2, y: geometry.size.height * positions.down)
        }
        .ignoresSafeArea()
    }

    //the text runs along the edge, read from bottom to top
    private func label(sign: String, action: String, spoken: String, length: CGFloat) -> some View {
        Button(action: onTap) {
            Text("\(sign) \(action)")
                .font(.caption2.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.large)     //has to fit the margin
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: width, height: length)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: width / 2))
                .minimumTapArea()       //the slim tab is easier to hit
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(spoken): \(action)")
    }
}
