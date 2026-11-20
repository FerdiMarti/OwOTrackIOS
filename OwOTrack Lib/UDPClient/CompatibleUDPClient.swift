//
//  CompatibleUDPClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 15.12.22.
//

import Foundation

//why a connection can't be used: a reason for the log, whether it will recover,
//and whether it's because iOS blocks the app from the local network
struct ConnectionProblem {
    let reason: String
    let fatal: Bool
    var localNetworkDenied = false
}

//Protocol for the UDP client (NWConnectionUDPClient). It once switched between clients for old iOS versions;
//now it keeps the network layer replaceable, e.g. by a fake connection in tests
protocol CompatibleUDPClient {
    //cb is called once the connection can be used. onProblem reports why it can't be used
    func open(cb: @escaping () -> Void, onProblem: @escaping (ConnectionProblem) -> Void) -> Void

    func close() -> Void

    func sendUDP(_ content: Data) -> Void

    //cb gets nil if receiving failed
    func receiveUDP(cb: @escaping (Data?) -> Void) -> Void
}
