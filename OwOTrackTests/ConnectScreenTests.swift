//
//  ConnectScreenTests.swift
//  OwOTrackTests
//
//  Input checks and states of the connect screen (ConnectionModel), shared by the iPhone and watch apps.
//

import Foundation
import CoreLocation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Connect screen")
    struct ConnectScreen {

        @Test("valid addresses: IPv4 addresses and computer names", arguments: [
            "192.168.1.230", "10.0.0.1", "0.0.0.0", "255.255.255.255",
            "DESKTOP-AB12CD.local", "my-pc.local", "desktop-ab12cd.fritz.box", "localhost", "pc1", "a.b.c.d",
            String(repeating: "a", count: 63) + ".local",
        ])
        func validAddress(_ address: String) {
            #expect(ConnectionModel.isValidAddress(address))
        }

        @Test("invalid addresses", arguments: [
            "", "192.168.1", "192.168.1.256", "192.168.1.1.1", "192..1.1", " 192.168.1.1", "+1.2.3.4", "1234.1.1.1",
            "fe80::1", "-pc.local", "pc-.local", "my_pc.local", "my pc", "pc..local", "my-pc.local.", "dé-pc.local",
            String(repeating: "a", count: 64) + ".local",
        ])
        func invalidAddress(_ address: String) {
            #expect(!ConnectionModel.isValidAddress(address))
        }

        @Test("a computer name isn't taken for an IP address")
        func nameIsNotIP() {
            #expect(!ConnectionModel.isValidIPAddress("my-pc.local"))
            #expect(ConnectionModel.isValidComputerName("my-pc.local"))
            #expect(!ConnectionModel.isValidComputerName("192.168.1.230"))
        }

        @Test("valid ports", arguments: ["0", "6969", "65535"])
        func validPort(_ port: String) {
            #expect(ConnectionModel.isValidPort(port))
        }

        @Test("invalid ports", arguments: ["", "-1", "65536", "69a", " 6969"])
        func invalidPort(_ port: String) {
            #expect(!ConnectionModel.isValidPort(port))
        }

        @Test("what can be edited and what the button does in each state")
        @MainActor
        func states() async {
            let model = ConnectionModel(sharing: nil)
            //the model updates on the main thread
            func show(_ change: () -> Void) async {
                change()
                await pause(0.05)
            }
            #expect(model.canEdit && !model.canDisconnect)

            await show { model.setLoading() }
            #expect(model.isConnecting && !model.canEdit && !model.canDisconnect)

            await show { model.setConnected() }
            #expect(model.isConnected && !model.canEdit && model.canDisconnect)

            await show { model.setServerType(.slimeVR) }
            #expect(model.serverType == .slimeVR)

            let giveUp = Date().addingTimeInterval(600)
            await show { model.setReconnecting(until: giveUp) }
            #expect(model.isReconnecting && !model.canEdit && model.canDisconnect)
            #expect(model.reconnectDeadline == giveUp)
            #expect(model.serverType == .slimeVR)      //still the same server it tries to reach

            await show { model.setFailed("Couldn't reconnect for 10 minutes") }
            #expect(model.status == .failed("Couldn't reconnect for 10 minutes"))
            #expect(model.canEdit && !model.canDisconnect)
            #expect(model.serverType == .unknown)
            #expect(model.reconnectDeadline == nil)

            await show { model.setLocalNetworkAccess(.granted) }
            #expect(model.localNetwork == .granted)

            await show { model.setUnconnected() }
            #expect(model.canEdit && !model.canDisconnect)
        }

        @Test("connected servers are remembered: newest first, no duplicates, at most 5")
        @MainActor
        func recentServers() async {
            clearRecentServers()
            defer { clearRecentServers() }
            //a list saved by an earlier version, without dates, keeps its order
            UserDefaults.standard.set([["address": "old1.local", "port": "6969"], ["address": "old2.local", "port": "7000"]],
                                      forKey: RECENT_SERVERS_USERDEFAULTS_KEY)
            #expect(ConnectionModel(sharing: nil).recentServers.map(\.id) == ["old1.local:6969", "old2.local:7000"])
            clearRecentServers()

            let model = ConnectionModel(sharing: nil)
            #expect(model.recentServers.isEmpty)
            for address in ["a.local", "b.local", "a.local", "c.local", "d.local", "e.local", "f.local"] {
                model.ip = address
                model.setConnected()
                await pause(0.05)
                model.setUnconnected()
                await pause(0.05)
            }
            let expected = ["f.local", "e.local", "d.local", "c.local", "a.local"]
            #expect(model.recentServers.map(\.address) == expected)
            #expect(ConnectionModel(sharing: nil).recentServers.map(\.address) == expected)    //saved for the next start

            model.useRecentServer(RecentServer(address: "c.local", port: "7000"))
            #expect(model.ip == "c.local")
            #expect(model.port == "7000")
        }

        @Test("the last server connected to is filled in on the next start, also on the watch")
        @MainActor
        func lastServerFilledIn() async {
            let keys = [IP_USERDEFAULTS_KEY, PORT_USERDEFAULTS_KEY, MAGNETOMETER_USERDEFAULTS_KEY]
            let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
            defer { zip(keys, saved).forEach { UserDefaults.standard.set($1, forKey: $0) } }
            clearRecentServers()
            defer { clearRecentServers() }
            //the watch's model: its service (the relay) doesn't save anything itself
            let model = ConnectionModel(service: RelayClient(transport: LoopbackTransport.pair().watch, hardware: FakeWatchHardware(),
                                                             motion: FakeMotion()), sharing: nil)
            model.ip = "my-pc.local"
            model.port = "7000"
            model.useMagnetometer = false
            model.setConnected()
            await pause(0.05)
            let next = ConnectionModel(sharing: nil)
            #expect(next.ip == "my-pc.local")
            #expect(next.port == "7000")
            #expect(next.useMagnetometer == false)
        }

        @Test("the iPhone and the watch show each other's recent servers: newest first, each once, at most 5")
        @MainActor
        func recentServersOfPairedDevice() async {
            clearRecentServers()
            defer { clearRecentServers() }
            let sharing = FakeRecentServerSharing()
            let model = ConnectionModel(sharing: sharing)
            #expect(sharing.shared.map { $0.map(\.id) } == [[]])        //its own list, when the app starts
            model.port = "6969"         //the same server only with the same port
            model.ip = "pc.local"
            model.setConnected()
            await pause(0.05)
            #expect(sharing.shared.last?.map(\.address) == ["pc.local"])

            //the paired device's list arrives: a newer server, one this device has too (used here more recently), an older one
            let now = Date()
            sharing.onPairedRecentServers?([
                RecentServer(address: "watch-new.local", port: "6969", used: now.addingTimeInterval(60)),
                RecentServer(address: "pc.local", port: "6969", used: now.addingTimeInterval(-60)),
                RecentServer(address: "watch-old.local", port: "6969", used: now.addingTimeInterval(-120)),
            ])
            #expect(model.recentServers.map(\.address) == ["watch-new.local", "pc.local", "watch-old.local"])

            //this device sends only its own servers, so they don't bounce back and forth
            model.ip = "laptop.local"
            model.setConnected()
            await pause(0.05)
            #expect(sharing.shared.last?.map(\.address) == ["laptop.local", "pc.local"])

            //a new list from the paired device replaces its old one; together at most 5
            sharing.onPairedRecentServers?((1...6).map { RecentServer(address: "w\($0).local", port: "6969", used: now.addingTimeInterval(-Double($0) * 1000)) })
            let expected = ["laptop.local", "pc.local", "w1.local", "w2.local", "w3.local"]
            #expect(model.recentServers.map(\.address) == expected)
            #expect(ConnectionModel(sharing: nil).recentServers.map(\.address) == expected)       //saved for the next start
        }

        @Test("volume button positions: the iPhone 17 from Apple's drawing; unknown models get the estimate")
        func volumeButtonPositions() throws {
            let iPhone17 = try #require(VolumeButtonPositions.forModel("iPhone18,3"))
            #expect(abs(iPhone17.up - 0.3162) < 0.0005)     //(48.23 - 2.44) / 144.79
            #expect(abs(iPhone17.down - 0.4143) < 0.0005)   //(62.43 - 2.44) / 144.79
            let se = try #require(VolumeButtonPositions.forModel("iPhone14,6"))
            #expect(abs(se.up - 0.1669) < 0.0005)           //(34.56 - 17.19) / 104.05: a big border above the screen
            #expect(VolumeButtonPositions.forModel("iPhone99,9") == .estimate)
            #expect(VolumeButtonPositions.forModel("arm64") == .estimate)
        }

        @Test("the iPhone Duo has its volume buttons on top: no labels at the side")
        func volumeButtonsOnTop() {
            #expect(VolumeButtonPositions.forModel("iPhone19,4") == nil)
            #expect(!VolumeButtonPositions.models.contains { $0.identifiers.contains("iPhone19,4") })
        }

        @Test("the table lists each model once, with positions that fit a phone")
        func volumeButtonTable() {
            var seen = Set<String>()
            for model in VolumeButtonPositions.models {
                for identifier in model.identifiers {
                    #expect(identifier.hasPrefix("iPhone"), "\(model.name): \(identifier)")
                    #expect(seen.insert(identifier).inserted, "\(identifier) is listed twice")
                }
                #expect(model.positions.up > 0.1 && model.positions.up < 0.5, "\(model.name): up \(model.positions.up)")
                #expect(model.positions.down > model.positions.up + 0.05 && model.positions.down < 0.6, "\(model.name): down \(model.positions.down)")
            }
        }

        @Test("the app reads the model it runs on (in the simulator: the simulated one)")
        func deviceModel() {
            #expect(VolumeButtonPositions.deviceModel.hasPrefix("iPhone") || VolumeButtonPositions.deviceModel.hasPrefix("iPad"))
            #expect(VolumeButtonPositions.current == VolumeButtonPositions.forModel(VolumeButtonPositions.deviceModel))
        }

        @Test("permission colors", arguments: [
            (CLAuthorizationStatus.authorizedAlways, PermissionState.good),
            (.authorizedWhenInUse, .limited),
            (.notDetermined, .limited),
            (.denied, .off),
            (.restricted, .off),
        ])
        func locationPermission(status: CLAuthorizationStatus, state: PermissionState) {
            #expect(PermissionState.location(status) == state)
        }

        @Test("local network: grey until a connection worked or was blocked")
        func localNetworkPermission() {
            #expect(PermissionState.localNetwork(.unknown) == .unknown)
            #expect(PermissionState.localNetwork(.granted) == .good)
            #expect(PermissionState.localNetwork(.denied) == .off)
            #expect(PermissionState.unknown.color == .gray)
        }

        @Test("every explanation has a title and text; the permissions also say their state and offer Settings")
        func explanations() {
            let topics: [InfoTopic] = [.address, .port, .magnetometer, .server(.slimeVR), .server(.owoTrackDriver), .reconnecting,
                                       .cantConnect, .location, .localNetwork, .screen, .volumeButtons, .watch]
            for topic in topics {
                let content = InfoContent(topic, localNetwork: .unknown, location: .authorizedWhenInUse)
                #expect(!content.title.isEmpty)
                #expect(!content.paragraphs.isEmpty)
                let isPermission = topic == .location || topic == .localNetwork
                #expect(content.offersSettings == isPermission)
                #expect((content.state != nil) == isPermission)
            }
            #expect(InfoContent(.location, localNetwork: .unknown, location: .authorizedWhenInUse).stateText.contains("only while using"))
            #expect(InfoContent(.localNetwork, localNetwork: .unknown, location: .denied).stateText.contains("Not checked yet"))
        }

        @Test("a wrong address or port is reported instead of connecting")
        @MainActor
        func wrongInput() {
            let model = ConnectionModel(sharing: nil)
            model.ip = "192.168.1"
            model.connectPressed()
            guard case .error(let message) = model.status else {
                Issue.record("no error for a wrong address")
                return
            }
            #expect(message.contains("IP address or computer name"))

            model.ip = "192.168.1.230"
            model.port = "70000"
            model.connectPressed()
            guard case .error(let portMessage) = model.status else {
                Issue.record("no error for a wrong port")
                return
            }
            #expect(portMessage.contains("port"))
        }
    }
}

private func clearRecentServers() {
    UserDefaults.standard.removeObject(forKey: RECENT_SERVERS_USERDEFAULTS_KEY)
    UserDefaults.standard.removeObject(forKey: PAIRED_RECENT_SERVERS_USERDEFAULTS_KEY)
}

//instead of WatchConnectivity: records what the model shares, and the test delivers the paired device's list
private final class FakeRecentServerSharing: RecentServerSharing {
    var shared: [[RecentServer]] = []
    var onPairedRecentServers: (([RecentServer]) -> Void)?

    func shareRecentServers(_ servers: [RecentServer]) {
        shared.append(servers)
    }
}
