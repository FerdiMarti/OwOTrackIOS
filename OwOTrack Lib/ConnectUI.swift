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
    
    func setMagnometerToggle(use: Bool)
    
    func updateLogs(text: String)
}
