//
//  TrackingService.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation
import CoreLocation
import UIKit

let TRACKING_SERVICE_QUEUE_LABEL = "TrackingService"
let IP_USERDEFAULTS_KEY = "ip"
let PORT_USERDEFAULTS_KEY = "port"
let MAGNETOMETER_USERDEFAULTS_KEY = "useM"

//how long connecting and reconnecting wait. The tests use shorter times
struct ConnectionTiming {
    var heartbeatTimeout: TimeInterval = 10     //no message from the server for that long: the connection is lost
    var connectTimeout: TimeInterval = 5        //how long one attempt waits for the handshake
    var reconnectPause: TimeInterval = 2        //pause between reconnect attempts
    //after that, reconnecting gives up and the session ends, so a forgotten phone doesn't keep its screen on and keep trying
    var reconnectTimeLimit: TimeInterval = 10 * 60
}

//manages connection, app and UI state
public class TrackingService: NSObject, CLLocationManagerDelegate {
    var ipAdress = ""
    var port = ""
    var magnetometer = true
    var connectUI: ConnectUI?  // the UI component that needs to be updated when status changes
    let logger = Logger.getInstance()
    var gHandler: GyroHandler?
    var client: UDPGyroProviderClient?  //the current connection attempt or connection, only assigned on the main thread
    var batteryTimer : Timer?   //timer that triggers sending of current battery level ever 10s
    var trackingServiceQueue = DispatchQueue.init(label: TRACKING_SERVICE_QUEUE_LABEL)

    //session state, also read by the reconnect loop on trackingServiceQueue, so guarded by a lock.
    //session counts start() and stop() calls: a reconnect loop of an earlier session sees it's outdated and ends
    private let stateLock = NSLock()
    private var session = 0
    private var wantsConnection = false     //between start() and stop(): a lost connection is retried
    private var reconnecting = false
    var timing = ConnectionTiming()     //set before start()

    //the device's hardware (sensors aside): iPhone or Apple Watch, a fake in the tests
    let hardware: any DeviceHardware.Type
    #if os(iOS)
    static let deviceHardware: any DeviceHardware.Type = IPhoneHardware.self
    #elseif os(watchOS)
    static let deviceHardware: any DeviceHardware.Type = WatchHardware.self
    #endif

    init(hardware: any DeviceHardware.Type = TrackingService.deviceHardware) {
        self.hardware = hardware
        super.init()
    }

    func start(ipAdress: String, port: String, magnetometer: Bool, connectUI: ConnectUI) {
        self.connectUI = connectUI
        self.ipAdress = ipAdress
        self.port = port
        self.magnetometer = magnetometer
        self.setDefaults()
        let session = beginSession()
        connectUI.setLoading()
        hardware.startProximitySensor()
        hardware.preventAutoLock()
        hardware.registerVolButtonListener(target: self)
        hardware.startBackgroundUsage(target: self)
        trackingServiceQueue.async {
            guard let client = self.connect(session: session, quiet: false, lastProblem: nil) else {
                return
            }
            if client.isConnected {
                self.logger.addEntry("Connection established")
                connectUI.setConnected()
                self.startStreaming(client: client)
            } else {
                //only a connection that worked is retried: if the first try fails, the address or the setup is likely wrong
                self.logger.addEntry("Handshake Failed")
                self.logger.addEntry("\nConnection timed out. Ensure IP and port are correct, that the server is running and not blocked by Windows Firewall (try changing your network type to private in Windows, or running the firewall script) or blocked by router, and that you're connected to the same network (you may need to disable Mobile Data) \n")
                self.logger.addEntry("Connecting Failed")
                self.stop()
            }
        }
    }

    //one connection attempt with a new client, so nothing of an earlier connection carries over (packet numbers,
    //SlimeVR detection, sensor description). Connects, sends the handshake and waits up to connectTimeout for a reply.
    //runs on trackingServiceQueue. Returns the client, connected or not, or nil if the session ended before the attempt
    private func connect(session: Int, quiet: Bool, lastProblem: String?) -> UDPGyroProviderClient? {
        if !isActive(session) {
            return nil
        }
        let client = UDPGyroProviderClient(host: ipAdress, port: port, service: self)
        client.quiet = quiet
        client.lastProblem = lastProblem
        DispatchQueue.main.sync { self.client = client }
        client.connectToUDP()
        let deadline = Date().addingTimeInterval(timing.connectTimeout)
        while !client.isConnected && Date() < deadline && isActive(session) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return client
    }

    //sends sensor data, battery level and the sensor description over a connected client
    private func startStreaming(client: UDPGyroProviderClient) {
        startSendingBattery()
        gHandler = GyroHandler.getInstance()
        gHandler?.startUpdates(client: client, useMagn: magnetometer)
        client.provideMagnetometerUse(enabled: magnetometer)
        client.provideSensorInfo(magnetometerSupported: gHandler?.magnetometerCorrectionAvailable ?? false, magnetometerEnabled: magnetometer)
    }

    private func stopStreaming() {
        stopSendingBattery()
        gHandler?.stopUpdates()
    }

    //a working connection was lost: no message from the server for 10 s, or the network failed. Called by the client on the main thread.
    //instead of ending the session, keep it (background running, no auto-lock, volume buttons) and connect again
    //until that works or the user presses Disconnect. Helps when SlimeVR restarts or the Wi-Fi drops for a moment
    func connectionLost(client lostClient: UDPGyroProviderClient) {
        guard lostClient === client, let session = beginReconnecting() else {
            return
        }
        stopStreaming()
        lostClient.disconnectUDP(logIt: false)
        logger.addEntry("Reconnecting...")
        connectUI?.setReconnecting()
        trackingServiceQueue.async {
            self.reconnect(session: session)
        }
    }

    //tries to connect every few seconds until it works, the session ends or reconnectTimeLimit is up. Runs on trackingServiceQueue
    private func reconnect(session: Int) {
        let giveUp = Date().addingTimeInterval(timing.reconnectTimeLimit)
        var lastProblem: String? = nil      //handed to the next attempt, so a reason is logged once and not on every attempt
        while let attempt = connect(session: session, quiet: true, lastProblem: lastProblem) {
            if attempt.isConnected {
                DispatchQueue.main.async {
                    guard attempt === self.client, self.finishReconnecting(session) else {
                        attempt.disconnectUDP(logIt: false)
                        return
                    }
                    self.logger.addEntry("Reconnected")
                    self.connectUI?.setConnected()
                    self.startStreaming(client: attempt)
                }
                return
            }
            lastProblem = attempt.lastProblem
            attempt.disconnectUDP(logIt: false)
            if Date() >= giveUp {
                DispatchQueue.main.async {
                    if self.isActive(session) {     //not if the user disconnected in the meantime
                        self.logger.addEntry("Couldn't reconnect for \(self.describe(self.timing.reconnectTimeLimit)), stopped trying")
                        self.stop()
                    }
                }
                return
            }
            let next = Date().addingTimeInterval(timing.reconnectPause)
            while Date() < next && isActive(session) {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    //"10 minutes", or "3 seconds" for the short limits in the tests
    private func describe(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) minutes" : "\(seconds) seconds"
    }

    // MARK: session state

    private func beginSession() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        session += 1
        wantsConnection = true
        reconnecting = false
        return session
    }

    private func endSession() {
        stateLock.lock()
        defer { stateLock.unlock() }
        session += 1
        wantsConnection = false
        reconnecting = false
    }

    private func isActive(_ session: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return wantsConnection && self.session == session
    }

    //returns the session to reconnect, or nil if the user disconnected or a reconnect is already running
    private func beginReconnecting() -> Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if !wantsConnection || reconnecting {
            return nil
        }
        reconnecting = true
        return session
    }

    //false if the session ended while the last attempt connected
    private func finishReconnecting(_ session: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if !wantsConnection || self.session != session {
            return false
        }
        reconnecting = false
        return true
    }
    
    func setDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(self.ipAdress, forKey: IP_USERDEFAULTS_KEY)
        defaults.set(self.port, forKey: PORT_USERDEFAULTS_KEY)
        defaults.set(self.magnetometer, forKey: MAGNETOMETER_USERDEFAULTS_KEY)
    }
    
    //ends the session: the user pressed Disconnect (also while reconnecting), or the first connection attempt failed
    func stop() {
        endSession()
        hardware.stopProximitySensor()
        hardware.allowAutoLock()
        hardware.unregisterVolButtonListener(target: self)
        hardware.stopBackgroundUsage()
        stopStreaming()
        client?.disconnectUDP()
        if (client?.isConnected) != nil && !client!.isConnected {
            connectUI?.setUnconnected()
            logger.addEntry("Disconnected")
        }
    }
    
    func toggleMagnetometerUse(use: Bool) {
        if client == nil {
            return
        }
        self.magnetometer = use
        gHandler?.stopUpdates()
        gHandler?.startUpdates(client: client!, useMagn: use)
        connectUI?.setMagnometerToggle(use: use)
        client?.sensorConfigChanged(magnetometerEnabled: use)
    }
    
    //handler for volume button presses, which show up as changes of the output volume.
    //the old and new volume tell which button it was; if they're missing, it counts as volume up
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            let oldVolume = (change?[.oldKey] as? NSNumber)?.floatValue ?? 0
            let newVolume = (change?[.newKey] as? NSNumber)?.floatValue ?? 0
            client?.provideButtonPushed(volumeUp: newVolume >= oldVolume)
        }
    }
    
    func startSendingBattery() {
        //all on the main thread, where the battery level is read: monitoring has to be enabled before the first read
        DispatchQueue.main.async {
            self.hardware.startBatteryLevelMonitoring()
            self.sendBatteryLevel()
            self.batteryTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(self.sendBatteryLevel), userInfo: nil, repeats: true)
        }
    }

    //skipped while the level is unknown, instead of reporting a full battery
    @objc func sendBatteryLevel() {
        if let level = hardware.getBatteryLevel() {
            self.client?.provideBatteryLevel(level: level)
        }
    }
    
    func stopSendingBattery() {
        batteryTimer?.invalidate()
        hardware.stopBatteryLevelMonitoring()
    }
}
