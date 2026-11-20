//
//  ConectUI.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 22.12.22.
//

import Foundation

//protocol to abstract the UI component on iOS and watchOS
protocol ConnectUI {
    
    func setLoading()
    
    func setConnected()
    
    func setUnconnected()

    //a working connection was lost and the app is trying to connect again
    func setReconnecting()

    func setMagnometerToggle(use: Bool)

    //called from any thread while the Logger holds its lock:
    //dispatch the UI update to the main queue and never call the Logger from here
    func updateLogs(text: String)
}
