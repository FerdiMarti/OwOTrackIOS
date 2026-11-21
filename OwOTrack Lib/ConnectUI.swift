//
//  ConectUI.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 22.12.22.
//

import Foundation

//what the app is connected to, found out while connecting
enum ServerType: String, Codable {
    case unknown            //not connected, or not found out yet
    case slimeVR            //acknowledged the sensor description
    case owoTrackDriver     //only answered the short handshake of the old protocol

    var name: String? {
        switch self {
        case .unknown: return nil
        case .slimeVR: return "SlimeVR"
        case .owoTrackDriver: return "owoTrack driver"
        }
    }
}

//whether iOS lets the app reach devices on the local network. iOS doesn't tell apps,
//so it's only known after a connection worked or was blocked
enum LocalNetworkAccess {
    case unknown, granted, denied
}

//protocol to abstract the UI component on iOS and watchOS. Called from any thread
protocol ConnectUI {

    func setLoading()

    func setConnected()

    func setUnconnected()

    //a working connection was lost and the app is trying to connect again, until the given time
    func setReconnecting(until giveUp: Date)

    //connecting failed, or reconnecting gave up. Comes after setUnconnected
    func setFailed(_ reason: String)

    func setServerType(_ type: ServerType)

    func setLocalNetworkAccess(_ access: LocalNetworkAccess)

    func setMagnometerToggle(use: Bool)

    //called from any thread while the Logger holds its lock:
    //dispatch the UI update to the main queue and never call the Logger from here
    func updateLogs(text: String)
}
