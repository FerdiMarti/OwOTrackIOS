//
//  Permissions.swift
//  OwOTrack
//

import SwiftUI
import CoreLocation

//how well a permission is set for the app: all good, works with limits, off, or not known yet
enum PermissionState {
    case good, limited, off, unknown

    var color: Color {
        switch self {
        case .good: return .green
        case .limited: return .yellow
        case .off: return .red
        case .unknown: return .gray
        }
    }

    //a symbol next to the color, so the state doesn't depend on telling colors apart
    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.circle.fill"
        case .off: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    //for VoiceOver
    var spokenName: String {
        switch self {
        case .good: return "all good"
        case .limited: return "limited"
        case .off: return "off"
        case .unknown: return "not checked yet"
        }
    }

    //location: only "Always" keeps the app running in the background. Not asked yet counts as limited:
    //the app asks when connecting, and iOS offers "While Using" first
    static func location(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedAlways: return .good
        case .authorizedWhenInUse, .notDetermined: return .limited
        case .denied, .restricted: return .off
        @unknown default: return .unknown
        }
    }

    //local network: iOS doesn't tell apps, so it's known only after a connection worked or was blocked
    static func localNetwork(_ access: LocalNetworkAccess) -> PermissionState {
        switch access {
        case .granted: return .good
        case .denied: return .off
        case .unknown: return .unknown
        }
    }
}

//the app's location permission, updated when the user changes it (e.g. in Settings while the app is in the background)
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()   //only reads the permission, never starts location updates

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var state: PermissionState {
        return PermissionState.location(status)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
