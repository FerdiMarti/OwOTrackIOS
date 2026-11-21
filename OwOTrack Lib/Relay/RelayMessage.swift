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

//the bytes on the way. The first byte tells a control message (0, then JSON) from a batch of motion readings
//(1, then per reading its kind and its floats)
enum RelayPacket: Equatable {
    case message(RelayMessage)
    case samples([MotionSample])

    var data: Data {
        switch self {
        case .message(let message):
            let json = (try? JSONEncoder().encode(message)) ?? Data()
            return Data([0]) + json
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
        case 0:
            guard let message = try? JSONDecoder().decode(RelayMessage.self, from: Data(body)) else {
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
