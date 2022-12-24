//
//  CompatibleUDPClient.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 15.12.22.
//

import Foundation

//Protocol for UDP clients to abstract for uses in different iOS versions
protocol CompatibleUDPClient {
    func open(cb: @escaping () -> Void) -> Void
    
    func close() -> Void

    func sendUDP(_ content: Data) -> Void
    
    func receiveUDP(cb: @escaping (Data?) -> Void) -> Void
}
