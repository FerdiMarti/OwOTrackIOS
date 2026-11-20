//
//  ConnectScreenTests.swift
//  OwOTrackTests
//
//  Input checks and states of the connect screen (ConnectionModel), shared by the iPhone and watch apps.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

extension OwOTrackTests {
    @Suite("Connect screen")
    struct ConnectScreen {

        @Test("valid IP addresses", arguments: ["192.168.1.230", "10.0.0.1", "0.0.0.0", "255.255.255.255"])
        func validAddress(_ address: String) {
            #expect(ConnectionModel.isValidIPAddress(address))
        }

        @Test("invalid IP addresses", arguments: [
            "", "192.168.1", "192.168.1.256", "192.168.1.1.1", "192..1.1", " 192.168.1.1", "a.b.c.d", "fe80::1", "my-pc.local",
        ])
        func invalidAddress(_ address: String) {
            #expect(!ConnectionModel.isValidIPAddress(address))
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
            let model = ConnectionModel()
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

            await show { model.setReconnecting() }
            #expect(model.isReconnecting && !model.canEdit && model.canDisconnect)

            await show { model.setUnconnected() }
            #expect(model.canEdit && !model.canDisconnect)
        }

        @Test("a wrong address or port is reported instead of connecting")
        @MainActor
        func wrongInput() {
            let model = ConnectionModel()
            model.ip = "192.168.1"
            model.connectPressed()
            guard case .error(let message) = model.status else {
                Issue.record("no error for a wrong address")
                return
            }
            #expect(message.contains("ip address"))

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
