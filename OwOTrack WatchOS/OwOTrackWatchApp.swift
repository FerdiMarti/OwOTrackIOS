//
//  OwOTrackWatchApp.swift
//  OwOTrack WatchOS
//

import SwiftUI
import Combine
import WatchKit

@main
struct OwOTrackWatchApp: App {
    //tracks through the iPhone app (RelayClient)
    @StateObject private var model: ConnectionModel
    private let feedback: StatusFeedback

    init() {
        let model = ConnectionModel()
        _model = StateObject(wrappedValue: model)
        feedback = StatusFeedback(model: model)
        //a session saved to Health shows on the iPhone too
        WorkoutRecorder.shared.onSaved = { summary in
            WatchConnectivityTransport.shared.send(.workout(summary))
        }
        WatchConnectivityTransport.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ConnectView(model: model)
                #if DEBUG
                .onAppear {
                    model.runScreenshotAction()
                    WorkoutRecorder.shared.runScreenshotAction()
                }
                #endif
        }
    }
}

//felt on the wrist: connected, connection lost, connecting failed; and VoiceOver says every change.
//Follows the model, not the screen, so it also comes with the wrist down, when the screen isn't updated
final class StatusFeedback {
    private var subscription: AnyCancellable?

    init(model: ConnectionModel) {
        subscription = model.$status.removeDuplicates().dropFirst().sink { status in
            switch status {
            case .connected: WKInterfaceDevice.current().play(.success)
            case .reconnecting: WKInterfaceDevice.current().play(.retry)
            case .failed: WKInterfaceDevice.current().play(.failure)
            default: break
            }
            if #available(watchOS 10.0, *) {
                AccessibilityNotification.Announcement(status.title).post()
            }
        }
    }
}
