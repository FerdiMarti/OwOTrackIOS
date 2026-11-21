//
//  RelayMessage.swift
//  OwOTrack
//
//  What the watch app and the iPhone app send each other for the relay: the watch can't reach the server itself
//  (watchOS blocks that kind of network connection), so the iPhone connects for it.
//

import Foundation

//control messages, sent as JSON
enum RelayMessage: Codable, Equatable {
    //watch → iPhone
    case start(RelayStart)              //connect for the watch (also sent again while the iPhone doesn't answer)
    case stop(session: UUID)            //ends that session (a late one doesn't end a newer session)
    case battery(Float)
    case reset(yaw: Bool)               //yaw reset, else full reset
    case alive                          //nothing else to send for a while (no motion readings, as in the simulator): still there
    case find(port: String, mac: [UInt8])   //search the network for the server (the watch's MAC: SlimeVR keeps it as the watch's tracker)
    //iPhone → watch
    case status(RelayStatus)            //the connection's state, also sent every few seconds as a sign of life
    case log([String])                  //new lines of the connection log
    case vibrate(frequency: Float, amplitude: Float, duration: Float)
    case magnetometer(Bool)             //use the magnetometer from now on (also when SlimeVR switches it)
    case found(ServerSearchResult)      //what the search found
}

//what the watch asks the iPhone to connect to, and how the watch identifies itself there
struct RelayStart: Codable, Equatable {
    var address: String
    var port: String
    var magnetometer: Bool
    var mac: [UInt8]                    //the watch's own, so SlimeVR shows it as its own tracker
    var magnetometerAvailable: Bool
    //new for every Connect on the watch: the same request sent again (the iPhone didn't answer yet) doesn't start over,
    //and the status messages of an earlier session are told apart
    var session = UUID()
}

struct RelayStatus: Codable, Equatable {
    enum State: String, Codable {
        case notConnected, connecting, connected, reconnecting, failed
    }

    var state: State
    var serverType = ServerType.unknown
    var giveUp: Date?                   //while reconnecting
    var reason: String?                 //why it failed, or why the iPhone ended it
    var session: UUID?                  //the watch's session it's about (RelayStart.session)

    var isActive: Bool {
        return state == .connecting || state == .connected || state == .reconnecting
    }
}

//one motion reading of the watch: big-endian floats as GyroHandler delivers them
struct MotionSample: Equatable {
    enum Kind: UInt8 {
        case rotation = 1       //x y z w
        case gyro = 2           //x y z
        case acceleration = 3   //x y z

        var count: Int {
            return self == .rotation ? 4 : 3
        }
    }

    let kind: Kind
    let values: [Data]
}

//which version of the relay messages this app speaks. The watch app can update later than the iPhone app (or the other
//way round): every control message carries both numbers, so an app that can't work with the other says which one to update
enum RelayProtocol {
    //raise for every change of the messages
    static let version: UInt8 = 1
    //the oldest version of the other app this one still works with: raise it only when an older app can no longer work
    //with this one (it can't read what this one sends, or this one needs something it doesn't send). Messages an app
    //doesn't know are ignored, so new messages and new optional fields don't need it
    static let oldestPeer: UInt8 = 1

    //the other app's version, and the oldest of this app's versions it works with
    static func isCompatible(peerVersion: UInt8, peerOldest: UInt8) -> Bool {
        return peerVersion >= oldestPeer && version >= peerOldest
    }
}

//the bytes on the way. The first byte tells a control message (0, the versions, then JSON) from a batch of motion
//readings (1, then per reading its kind and its floats) and the versions alone (2, the answer to an app that can't
//work with this one). The versions come first and never change their place, so every version can read them
enum RelayPacket: Equatable {
    case message(RelayMessage)
    case samples([MotionSample])
    case versions                           //sent: only this app's versions
    case incompatible(peerVersion: UInt8)   //received: the other app's version can't work with this one

    //what to show when the other app's version can't work with this one (newer: this app is the old one)
    static func updateHint(peerVersion: UInt8, onWatch: Bool) -> String {
        let thisIsOlder = peerVersion > RelayProtocol.version
        if onWatch {
            return thisIsOlder ? "Update OwOTrack on this watch" : "Update OwOTrack on your iPhone"
        }
        return thisIsOlder ? "Update OwOTrack on this iPhone to track with the watch" : "Update OwOTrack on your Apple Watch"
    }

    var data: Data {
        let versions = Data([RelayProtocol.version, RelayProtocol.oldestPeer])
        switch self {
        case .message(let message):
            let json = (try? JSONEncoder().encode(message)) ?? Data()
            return Data([0]) + versions + json
        case .versions, .incompatible:
            return Data([2]) + versions
        case .samples(let samples):
            var data = Data([1])
            for sample in samples {
                data.append(sample.kind.rawValue)
                for value in sample.values {
                    data.append(value.prefix(4))
                }
            }
            return data
        }
    }

    init(_ message: RelayMessage) {
        self = .message(message)
    }

    init(samples: [MotionSample]) {
        self = .samples(samples)
    }

    //nil for anything that isn't a valid packet
    init?(data: Data) {
        guard let first = data.first else {
            return nil
        }
        let body = data.dropFirst()
        switch first {
        case 0, 2:
            guard body.count >= 2 else {
                return nil
            }
            let peerVersion = body[body.startIndex], peerOldest = body[body.startIndex + 1]
            guard RelayProtocol.isCompatible(peerVersion: peerVersion, peerOldest: peerOldest) else {
                self = .incompatible(peerVersion: peerVersion)
                return
            }
            //a message this version doesn't know (from a newer app) is ignored, like the versions alone
            guard first == 0, let message = try? JSONDecoder().decode(RelayMessage.self, from: Data(body.dropFirst(2))) else {
                return nil
            }
            self = .message(message)
        case 1:
            var samples: [MotionSample] = []
            var bytes = [UInt8](body)[...]
            while let kindByte = bytes.first {
                guard let kind = MotionSample.Kind(rawValue: kindByte), bytes.count >= 1 + kind.count * 4 else {
                    return nil
                }
                bytes = bytes.dropFirst()
                var values: [Data] = []
                for _ in 0..<kind.count {
                    values.append(Data(bytes.prefix(4)))
                    bytes = bytes.dropFirst(4)
                }
                samples.append(MotionSample(kind: kind, values: values))
            }
            self = .samples(samples)
        default:
            return nil
        }
    }
}
