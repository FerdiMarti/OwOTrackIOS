//
//  InfoTopics.swift
//  OwOTrack
//
//  The explanations behind the ⓘ buttons. They replace the old Information tab:
//  each text now sits next to the part of the screen it explains.
//

import SwiftUI
import CoreLocation

enum InfoTopic: Identifiable, Equatable {
    case address
    case port
    case magnetometer
    case server(ServerType)
    case reconnecting
    case cantConnect
    case location
    case localNetwork
    case screen
    case volumeButtons
    case watch

    var id: String {
        switch self {
        case .server(let type): return "server-\(type)"
        default: return "\(self)"
        }
    }
}

//title, current state (for permissions) and paragraphs of a topic. Paragraphs can use **bold**
struct InfoContent {
    var title: String
    var state: PermissionState?
    var stateText = ""
    var paragraphs: [String]
    var offersSettings = false

    init(_ topic: InfoTopic, localNetwork: LocalNetworkAccess, location: CLAuthorizationStatus) {
        switch topic {
        case .address:
            title = "Server Address"
            paragraphs = [
                "Leave it empty and Connect finds SlimeVR (or the owoTrack driver) on your Wi-Fi by itself. The search button next to the field does the same and fills in what it finds.",
                "Nothing found? Check that SlimeVR is running, that this iPhone is on the same Wi-Fi as the computer (not a guest network), that Local Network access is allowed for OwOTrack, and that the computer's firewall lets SlimeVR through.",
                "You can also enter the IP address of the computer running SlimeVR or the owoTrack driver, or the computer's name. A name keeps working when the computer gets a new IP address.",
                "On Windows 10/11 PCs and Macs, the name followed by .local usually works, for example **DESKTOP-AB12CD.local**. On Windows, the name is shown under Settings → System → About → Device name.",
                "The clock button lists the servers you connected to recently.",
            ]
        case .port:
            title = "Port"
            paragraphs = [
                "SlimeVR and the owoTrack driver both use port 6969, unless it was changed in their settings.",
            ]
        case .magnetometer:
            title = "Magnetometer"
            paragraphs = [
                "Turning the magnetometer off can improve latency and battery life, and avoids problems near magnets. It increases yaw drift, though: the tracker slowly turns around the vertical axis.",
                "**With SlimeVR**, SlimeVR controls the magnetometer and this switch follows it. Turn on \"Use magnetometer on all IMU trackers that support it\" in SlimeVR's settings, and \"Allow magnetometer\" in the tracker's settings. The switch sets the starting value.",
                "**With the owoTrack driver**, this switch controls it.",
            ]
        case .server(let type):
            title = type.name ?? "Server"
            if type == .owoTrackDriver {
                paragraphs = [
                    "Connected to the owoTrack driver for SteamVR.",
                    "The owoTrack driver is no longer maintained, so SlimeVR is recommended. The app keeps working with the driver.",
                ]
            } else {
                paragraphs = [
                    "Connected to SlimeVR Server. SlimeVR lists this iPhone as an owoTrack tracker, with the app version as its firmware.",
                    "SlimeVR is the recommended server: the owoTrack driver is no longer maintained.",
                ]
            }
        case .reconnecting:
            title = "Reconnecting"
            paragraphs = [
                "If a working connection drops, for example because SlimeVR restarted or the Wi-Fi was gone for a moment, the app keeps trying to reconnect for up to 10 minutes.",
                "Press Disconnect to stop it earlier.",
            ]
        case .cantConnect:
            title = "Can't Connect?"
            paragraphs = [
                "• Check the IP address or computer name, and the port.",
                "• Make sure SlimeVR or the owoTrack driver is running on the computer.",
                "• Windows Firewall may block the connection: set the network type to Private in Windows, or run SlimeVR's firewall script.",
                "• Your iPhone has to be on the same network as the computer. Turning off mobile data can help.",
                "• Some routers keep devices on the network from reaching each other.",
                "• OwOTrack needs Local Network access, see Permissions.",
                "The connection log at the bottom of the screen shows what happened.",
            ]
        case .location:
            title = "Location"
            let current: String
            switch location {
            case .authorizedAlways:
                current = "Allowed always. The app can keep tracking in the background and while the iPhone is locked."
            case .authorizedWhenInUse:
                current = "Allowed only while using the app. Tracking stops soon after the app goes to the background or the iPhone locks."
            case .notDetermined:
                current = "Not asked yet. The app asks when you connect for the first time."
            default:
                current = "Not allowed. Tracking only works while the app is open on screen."
            }
            state = PermissionState.location(location)
            stateText = current
            paragraphs = [
                "**Is it needed?** Not for tracking itself: everything works while the app is open. It's only needed to keep tracking in the background or while the iPhone is locked.",
                "Your location isn't used: the permission only keeps the app running in the background. The location never leaves your iPhone.",
                "Even with \"Always\", iOS may end apps in the background after 10 to 30 minutes. To avoid that, keep the app open: while connected, the iPhone doesn't lock automatically.",
                "**To change it:** Settings → OwOTrack → Location → Always.",
            ]
            offersSettings = true
        case .localNetwork:
            title = "Local Network"
            let current: String
            switch localNetwork {
            case .granted: current = "Allowed. The last connection worked."
            case .denied: current = "Blocked. The app can't reach the computer."
            case .unknown: current = "Not checked yet. iOS doesn't tell apps whether it's allowed, so this shows after the first connection."
            }
            state = PermissionState.localNetwork(localNetwork)
            stateText = current
            paragraphs = [
                "**Is it needed?** Yes. Without it, the app can't reach SlimeVR or the owoTrack driver on your computer.",
                "**To change it:** Settings → OwOTrack → Local Network.",
            ]
            offersSettings = true
        case .screen:
            title = "Screen"
            paragraphs = [
                "While connected, the iPhone doesn't lock automatically, so tracking keeps running.",
                "To save battery, the screen dims after 30 seconds without a touch. The last 5 seconds are counted down. Touch the screen to brighten it again; that touch doesn't press anything.",
                "You can also turn the screen off by covering the sensor at the top of the iPhone, next to the front camera. The app stays connected.",
            ]
        case .watch:
            title = "Apple Watch"
            paragraphs = [
                "Connect on your Apple Watch to track with it. The watch can't reach SlimeVR by itself, so this iPhone passes its readings on. In SlimeVR, the watch is a tracker of its own.",
                "Keep OwOTrack running on this iPhone while you track with the watch: leave it open (the screen dims), or allow Location \"Always\" so it can keep running in the background.",
                "This iPhone doesn't have to be connected as a tracker itself. The watch has its own server address, in its settings. Its recent servers include the ones this iPhone connected to, and the other way around.",
                "**Stop** ends the watch's connection from here.",
            ]
        case .volumeButtons:
            title = "Volume Buttons"
            paragraphs = [
                "While connected to SlimeVR, the volume buttons trigger a reset: **volume up** for a yaw reset, **volume down** for a full reset. SlimeVR's reset delays apply.",
                "Volume up doesn't register when the volume is already at the maximum, and volume down doesn't at the minimum.",
            ]
        }
    }
}

//an ⓘ button that opens an explanation
struct InfoButton: View {
    let subject: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(subject)")
    }
}

struct InfoSheet: View {
    let topic: InfoTopic
    @ObservedObject var model: ConnectionModel
    @ObservedObject var location: LocationPermission
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = InfoContent(topic, localNetwork: model.localNetwork, location: location.status)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let state = content.state {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: state.symbol)
                                .foregroundColor(state.color)
                            Text(content.stateText)
                                .fontWeight(.semibold)
                        }
                    }
                    ForEach(content.paragraphs, id: \.self) { paragraph in
                        Text(LocalizedStringKey(paragraph))     //LocalizedStringKey shows the **bold** parts
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if content.offersSettings {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .halfSheet()
    }
}

//the whole connection log, to read or copy for a support request
struct LogSheet: View {
    @ObservedObject var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationView {
            LogView(text: model.log, placeholder: "Nothing logged yet. The log fills up when you connect.")
                .padding()
                .navigationTitle("Connection Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = model.log
                            copied = true
                        }
                        .disabled(model.log.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}

extension View {
    //a sheet that first opens half high, where iOS supports it (16 and later). On iOS 15 it opens full height
    @ViewBuilder
    func halfSheet() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}
