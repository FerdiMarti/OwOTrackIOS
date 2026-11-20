//
//  Logger.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 05.04.21.
//

import Foundation

//Singleton that is used in most classes to add log entries to the UI
//It's called from several threads (UI, connection setup, network), so all state is guarded by a lock

class Logger {

    private var logEntries = Array<String>()
    private static let instance = Logger()  //static let is created exactly once, even if several threads ask for it at the same time
    private var connectUI : ConnectUI?
    private let lock = NSLock()

    private init() {

    }

    //attach the UI component that will be updated on new logs
    func attachUI(connectUI: ConnectUI) {
        lock.lock()
        defer { lock.unlock() }
        self.connectUI = connectUI
    }

    //clear logs
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        logEntries.removeAll()
        //updateLogs only queues the update on the main thread, so calling it under the lock is safe and keeps the updates in order
        connectUI?.updateLogs(text: text())
    }

    func addEntry(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        logEntries.append(entry)
        connectUI?.updateLogs(text: text())
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text()
    }

    //builds the log text, caller must hold the lock
    private func text() -> String {
        return logEntries.map { $0 + "\n" }.joined()
    }

    static func getInstance() -> Logger {
        return instance
    }
}
