//
//  InterfaceController.swift
//  OwOTrack WatchKit Extension
//
//  Created by Ferdinand Martini on 21.12.22.
//

import WatchKit
import Foundation
import UIKit


class InterfaceController: WKInterfaceController, ConnectUI {

    @IBOutlet weak var statusLabel: WKInterfaceLabel!
    @IBOutlet weak var ipField: WKInterfaceTextField!
    @IBOutlet weak var portField: WKInterfaceTextField!
    @IBOutlet weak var magnetometerToggle: WKInterfaceSwitch!
    @IBOutlet weak var connectButton: WKInterfaceButton!
    @IBOutlet weak var loggingLabel: WKInterfaceLabel!
    
    var ipFieldText : String? = ""
    var portFieldText: String? = ""
    var magnetometerToggleValue: Bool = true
    let defaults = UserDefaults.standard
    let tService = TrackingService()
    var isConnected = false
    var isLoading = false
    let logger = Logger.getInstance()
    
    //these are neccessare to track changes in textField values, only way to get text in fields
    @IBAction func ipFieldValueChange(_ value: NSString?) {
        ipFieldText = value as String?
    }
    
    @IBAction func portFieldValueChange(_ value: NSString?) {
        portFieldText = value as String?
    }
    
    @IBAction func magentometerToggleValueChange(_ value: Bool) {
        magnetometerToggleValue = value
    }
    
    override func awake(withContext context: Any?) {
        logger.attachUI(connectUI: self)
        setUnconnected()
        if let ipTemp = defaults.object(forKey: IP_USERDEFAULTS_KEY) as? String {
            ipFieldText = ipTemp
            ipField.setText(ipFieldText)
        } else {
            ipFieldText = "192.168.0.10"
            ipField.setText(ipFieldText)
            self.defaults.set(ipFieldText, forKey: IP_USERDEFAULTS_KEY)
        }
        if let portTemp = defaults.object(forKey: PORT_USERDEFAULTS_KEY) as? String {
            portFieldText = portTemp
            portField.setText(portFieldText)
        } else {
            portFieldText = "6969"
            portField.setText(portFieldText)
            self.defaults.set(portFieldText, forKey: PORT_USERDEFAULTS_KEY)
        }
        if let useMagnTemp = defaults.object(forKey: MAGNETOMETER_USERDEFAULTS_KEY) as? Bool {
            magnetometerToggle.setOn(useMagnTemp)
        } else {
            self.defaults.set(magnetometerToggleValue, forKey: MAGNETOMETER_USERDEFAULTS_KEY)
        }
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
    }
    
    func updateLogs(text: String) {
        DispatchQueue.main.async {
            self.loggingLabel.setText(text)
            self.scroll(to: self.loggingLabel, at: .bottom, animated: true)
        }
    }
    
    @IBAction func connectPushed(_ sender: Any) {
        if !validatePort(port: self.portFieldText) {
            setStatusError(text: "Please enter a valid port number")
            return
        }
        if !validateIPAddress(ip: self.ipFieldText) {
            setStatusError(text: "Please enter a valid ip address")
            return
        }
        if isConnected {
            tService.stop()
        } else if isLoading {
        
        } else {
            tService.start(ipAdress: ipFieldText != nil ? ipFieldText! : "", port: portFieldText != nil ? portFieldText! : "", magnetometer: magnetometerToggleValue, connectUI: self)
        }
    }
    
    func setStatusError(text: String) {
        self.statusLabel.setText(text)
        self.statusLabel.setTextColor(.red)
    }
    
    func setLoading() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.isConnected = false
            self.statusLabel.setText("Loading...")
            self.statusLabel.setTextColor(.none)
            self.ipField.setEnabled(false)
            self.portField.setEnabled(false)
            self.magnetometerToggle.setEnabled(false)
            self.connectButton.setEnabled(false)
            self.connectButton.setTitle("Connect")
            self.loggingLabel.setText("")
        }
    }
    
    func setConnected() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isConnected = true
            self.statusLabel.setText("Connected")
            self.statusLabel.setTextColor(.green)
            self.ipField.setEnabled(false)
            self.portField.setEnabled(false)
            self.magnetometerToggle.setEnabled(false)
            self.connectButton.setEnabled(true)
            self.connectButton.setTitle("Disconnect")
        }
    }
    
    func setUnconnected() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isConnected = false
            self.statusLabel.setText("Not Connected")
            self.statusLabel.setTextColor(.gray)
            self.ipField.setEnabled(true)
            self.portField.setEnabled(true)
            self.magnetometerToggle.setEnabled(true)
            self.connectButton.setEnabled(true)
            self.connectButton.setTitle("Connect")
        }
    }
    
    //used if server triggers a change in magnetometer use
    func setMagnometerToggle(use: Bool) {
        DispatchQueue.main.async {
            self.magnetometerToggle.setOn(use)
        }
    }
    
    func validatePort(port: String?) -> Bool {
        if port == "" || port == nil {
            return false
        }
        guard let nr = Int(port!) else {
            return false
        }
        if (nr < 0 || nr > 65535) {
            return false
        }
        return true
    }
    
    func validateIPAddress(ip: String?) -> Bool {
        if ip == "" || ip == nil {
            return false
        }
        let parts = ip!.split(separator: ".")
        if parts.count != 4 {
            return false
        }
        for part in parts {
            guard let nr = Int(part) else {
                return false
            }
            if nr < 0 || nr > 255 {
                return false
            }
        }
        return true
    }
}
