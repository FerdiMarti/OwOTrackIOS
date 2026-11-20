//
//  CompatibleUDPClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 15.12.22.
//

import Foundation

//Protocol for the UDP client (NWConnectionUDPClient). It once switched between clients for old iOS versions;
//now it keeps the network layer replaceable, e.g. by a fake connection in tests
protocol CompatibleUDPClient {
    //cb is called once the connection can be used.
    //onProblem reports why it can't be used, as text for the log; fatal means it won't recover
    func open(cb: @escaping () -> Void, onProblem: @escaping (_ reason: String, _ fatal: Bool) -> Void) -> Void

    func close() -> Void

    func sendUDP(_ content: Data) -> Void

    //cb gets nil if receiving failed
    func receiveUDP(cb: @escaping (Data?) -> Void) -> Void
}
