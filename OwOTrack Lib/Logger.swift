//
//  Logger.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 05.04.21.
//

import Foundation

//Singleton that is used in most classes to add log entries to the UI

class Logger {
    
    private var logEntries = Array<String>()
    private static var instance : Logger?
    private var connectUI : ConnectUI?
    
    init() {
        
    }
    
    //attach the UI component that will be updated on new logs
    func attachUI(connectUI: ConnectUI) {
        self.connectUI = connectUI
    }
    
    //clear logs
    func reset() {
        logEntries.removeAll()
        connectUI?.updateLogs(text: get())
    }
    
    func addEntry(_ entry: String) {
        self.logEntries.append(entry)
        connectUI?.updateLogs(text: get())
    }
    
    func get() -> String {
        var str = ""
        for string in logEntries {
            str = str + string + "\n"
        }
        return str
    }
    
    static func getInstance() -> Logger {
        if instance == nil {
            instance = Logger()
        }
        return instance!
    }
}
