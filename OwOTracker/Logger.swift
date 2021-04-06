//
//  Logger.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 05.04.21.
//

import Foundation

class Logger {
    
    private var logEntries = Array<String>()
    private static var instance : Logger?
    
    init() {
        
    }
    
    func reset() {
        logEntries.removeAll()
    }
    
    func addEntry(_ entry: String) {
        self.logEntries.append(entry)
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
