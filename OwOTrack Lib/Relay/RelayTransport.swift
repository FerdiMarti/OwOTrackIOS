//
//  RelayTransport.swift
//  OwOTrack
//

import Foundation

//how the relay's packets get between the watch and the iPhone: WatchConnectivity in the apps, a loopback in the tests.
//Received packets are delivered on the main thread
protocol RelayTransport: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    //what goes back with the confirmation of a received message (nil: nothing). The iPhone answers the watch's
    //messages with its status this way: iOS only delivers messages the iPhone sends by itself while it considers the
    //watch app reachable (screen on, or a workout running), but an answer always gets back. Called on the main thread
    var replyProvider: (() -> Data?)? { get set }
    //data that came back with a confirmation. Without it, that data goes to onReceive. On the main thread
    var onReply: ((Data) -> Void)? { get set }
    //whether the other side can be reached right now
    var isReachable: Bool { get }
    //onlyIfReachable: skip it while the other side can't be reached (motion readings).
    //Else the watch sends anyway, which wakes the iPhone app.
    //onConfirmed: called on the main thread once the other side confirmed it (true) or sending failed (false),
    //so the sender can limit how much is on its way. Returns false if it wasn't sent at all
    @discardableResult
    func send(_ data: Data, onlyIfReachable: Bool, onConfirmed: ((Bool) -> Void)?) -> Bool
}

extension RelayTransport {
    func send(_ message: RelayMessage) {
        send(RelayPacket(message).data, onlyIfReachable: false, onConfirmed: nil)
    }
}

#if canImport(WatchConnectivity)
import WatchConnectivity

final class WatchConnectivityTransport: NSObject, RelayTransport, RecentServerSharing, WCSessionDelegate {
    static let shared = WatchConnectivityTransport()
    private static let recentServersKey = "recentServers"

    var onReceive: ((Data) -> Void)?
    var replyProvider: (() -> Data?)?
    var onReply: ((Data) -> Void)?
    //activation, reachability or (on the iPhone) pairing changed. On the main thread
    var onStateChange: (() -> Void)?
    var onPairedRecentServers: (([RecentServer]) -> Void)? {
        didSet { deliverReceivedRecentServers() }
    }
    //this device's latest list, sent again whenever the session activates (also with another watch). On the main thread
    private var sharedRecentServers: [[String: Any]]?

    private var session: WCSession? {
        return WCSession.isSupported() ? WCSession.default : nil
    }

    //once, when the app starts, so messages that launch the app in the background are received
    func activate() {
        guard let session = session, session.delegate == nil else {
            return
        }
        session.delegate = self
        session.activate()
    }

    var isReachable: Bool {
        guard let session = session, session.activationState == .activated else {
            return false
        }
        return session.isReachable
    }

    #if os(iOS)
    //an Apple Watch is paired and has the watch app installed (only the TestFlight build includes it)
    var watchAppAvailable: Bool {
        guard let session = session, session.activationState == .activated else {
            return false
        }
        return session.isPaired && session.isWatchAppInstalled
    }
    #endif

    @discardableResult
    func send(_ data: Data, onlyIfReachable: Bool, onConfirmed: ((Bool) -> Void)?) -> Bool {
        guard let session = session, session.activationState == .activated else {
            return false
        }
        //the iPhone's messages are tried even while the watch doesn't look reachable: that flag can be behind, and
        //a message that can't be delivered just fails (the iPhone can't wake the watch app)
        if onlyIfReachable && !session.isReachable {
            return false
        }
        //with a reply handler, the other side confirms the message (see didReceiveMessageData with a reply handler),
        //and can send data back with the confirmation
        let replyHandler: ((Data) -> Void)? = onConfirmed.map { confirmed in
            { reply in
                DispatchQueue.main.async {
                    if !reply.isEmpty {
                        (self.onReply ?? self.onReceive)?(reply)
                    }
                    confirmed(true)
                }
            }
        }
        session.sendMessageData(data, replyHandler: replyHandler) { error in
            print("Relay: sending failed: \(error.localizedDescription)")
            if let confirmed = onConfirmed {
                DispatchQueue.main.async { confirmed(false) }
            }
        }
        return true
    }

    // MARK: recent servers, as the application context: the latest one is delivered, also to an app that isn't running

    func shareRecentServers(_ servers: [RecentServer]) {
        sharedRecentServers = servers.map(\.plist)
        flushRecentServers()
    }

    //on the main thread: once the session is active and (on the iPhone) the watch app is installed
    private func flushRecentServers() {
        guard let servers = sharedRecentServers, let session = session, session.activationState == .activated else {
            return
        }
        #if os(iOS)
        guard session.isPaired && session.isWatchAppInstalled else {
            return
        }
        #endif
        do {
            try session.updateApplicationContext([WatchConnectivityTransport.recentServersKey: servers])
        } catch {
            print("Relay: sharing the recent servers failed: \(error.localizedDescription)")
        }
    }

    //the last list the paired device shared, kept by WatchConnectivity
    private func deliverReceivedRecentServers() {
        guard let session = session, session.activationState == .activated else {
            return
        }
        deliver(session.receivedApplicationContext)
    }

    private func deliver(_ context: [String: Any]) {
        guard let servers = context[WatchConnectivityTransport.recentServersKey] as? [[String: Any]] else {
            return
        }
        onPairedRecentServers?(RecentServer.list(fromPlist: servers))
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.flushRecentServers()
            self.deliverReceivedRecentServers()
            self.onStateChange?()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.deliver(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        DispatchQueue.main.async { self.onReceive?(messageData) }
    }

    //a message the sender wants confirmed: handle it, then confirm it, with what the app has for the sender
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.onReceive?(messageData)
            replyHandler(self.replyProvider?() ?? Data())
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.onStateChange?() }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    //the user switched to another watch: start over with that one
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    //also when the watch app was just installed: it gets the recent servers then
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.flushRecentServers()
            self.onStateChange?()
        }
    }
    #endif
}
#endif
