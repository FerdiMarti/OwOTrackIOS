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
    @IBOutlet var ipLabel: WKInterfaceLabel!
    @IBOutlet var ipTapRecognizer: WKTapGestureRecognizer!
    @IBOutlet var portTapRecognizer: WKTapGestureRecognizer!
    @IBOutlet var portLabel: WKInterfaceLabel!
    @IBOutlet weak var magnetometerToggle: WKInterfaceSwitch!
    @IBOutlet weak var connectButton: WKInterfaceButton!
    @IBOutlet weak var loggingLabel: WKInterfaceLabel!
    
    var ipLabelText : String? = ""
    var portLabelText: String? = ""
    var magnetometerToggleValue: Bool = true
    let defaults = UserDefaults.standard
    let tService = TrackingService()
    var isConnected = false
    var isLoading = false
    let logger = Logger.getInstance()
    
    @IBAction func magentometerToggleValueChange(_ value: Bool) {
        magnetometerToggleValue = value
    }
    
    @IBAction func ipAddressTapped(_ sender: Any) {
        presentTextInputController(withSuggestions: [], allowedInputMode: WKTextInputMode.plain) { (arr: [Any]?) in
            self.ipChanged(to: arr?[0] as? String)
        }
    }
    
    @IBAction func portTapped(_ sender: Any) {
        presentTextInputController(withSuggestions: [], allowedInputMode: WKTextInputMode.plain) { (arr: [Any]?) in
            self.portChanged(to: arr?[0] as? String)
        }
    }
    
    func ipChanged(to: String?) {
        ipLabelText = to
        if to == "" {
            ipLabelText = nil
        }
        if ipLabelText != nil {
            ipLabel.setTextColor(.white)
            ipLabel.setText(ipLabelText)
        } else {
            ipLabel.setTextColor(.gray)
            ipLabel.setText("IP Address")
        }
    }
    
    func portChanged(to: String?) {
        portLabelText = to
        if to == "" {
            portLabelText = nil
        }
        if portLabelText != nil {
            portLabel.setTextColor(.white)
            portLabel.setText(portLabelText)
        } else {
            portLabel.setTextColor(.gray)
            portLabel.setText("Port")
        }
    }
    
    override func awake(withContext context: Any?) {
        logger.attachUI(connectUI: self)
        setUnconnected()
        if let ipTemp = defaults.object(forKey: IP_USERDEFAULTS_KEY) as? String {
            ipChanged(to: ipTemp)
        } else {
            ipChanged(to: "192.168.0.10")
            self.defaults.set(ipLabelText, forKey: IP_USERDEFAULTS_KEY)
        }
        if let portTemp = defaults.object(forKey: PORT_USERDEFAULTS_KEY) as? String {
            portChanged(to: portTemp)
        } else {
            portChanged(to: "6969")
            self.defaults.set(portLabelText, forKey: PORT_USERDEFAULTS_KEY)
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
            if #available(watchOSApplicationExtension 4.0, *) {
                self.scroll(to: self.loggingLabel, at: .bottom, animated: true)
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    @IBAction func connectPushed(_ sender: Any) {
        if !validatePort(port: self.portLabelText) {
            setStatusError(text: "Please enter a valid port number")
            return
        }
        if !validateIPAddress(ip: self.ipLabelText) {
            setStatusError(text: "Please enter a valid ip address")
            return
        }
        if isConnected {
            tService.stop()
        } else if isLoading {
        
        } else {
            tService.start(ipAdress: ipLabelText != nil ? ipLabelText! : "", port: portLabelText != nil ? portLabelText! : "", magnetometer: magnetometerToggleValue, connectUI: self)
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
            self.ipTapRecognizer.isEnabled = false
            self.portTapRecognizer.isEnabled = false
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
            self.ipTapRecognizer.isEnabled = false
            self.portTapRecognizer.isEnabled = false
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
            self.ipTapRecognizer.isEnabled = true
            self.portTapRecognizer.isEnabled = true
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
