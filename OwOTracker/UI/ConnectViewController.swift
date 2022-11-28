//
//  ViewController.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 01.05.21.
//

import UIKit

class ConnectViewController: UIViewController {
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var ipField: UITextField!
    @IBOutlet weak var portField: UITextField!
    @IBOutlet weak var magnetometerToggle: UISwitch!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var discoverButton: UIButton!
    @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
    @IBOutlet weak var loggingTextView: UITextView!
    
    let defaults = UserDefaults.standard
    let logger = Logger.getInstance()
    let tService = TrackingService()
    let discoverer = AutoDiscovery()
    
    var isConnected = false
    var isLoading = false
    
    override func viewDidLoad() {
        super.viewDidLoad()        
        logger.attachVC(cvc: self)
        setUnconnected()
        loadingIndicator.hidesWhenStopped = true
        self.navigationController?.title = "Connect"
        if let ipTemp = defaults.object(forKey: "ip") as? String {
            ipField.text = ipTemp
        } else {
            ipField.text = "192.168.0.1"
            self.defaults.set(ipField.text, forKey: "ip")
        }
        if let portTemp = defaults.object(forKey: "port") as? String {
            portField.text = portTemp
        } else {
            portField.text = "6969"
            self.defaults.set(portField.text, forKey: "port")
        }
        if let useMagnTemp = defaults.object(forKey: "useM") as? Bool {
            magnetometerToggle.isOn = useMagnTemp
        } else {
            self.defaults.set(magnetometerToggle.isOn, forKey: "useM")
        }
    }
    
    @IBAction func discoverPushed(_ sender: Any) {
        setLoading()
        discoverer.sendDiscovery(cb: { (error, ip, port) in
            if (error) {
                self.setUnconnected()
                return
            }
            self.ipField.text = ip
            self.portField.text = port
            self.setUnconnected()
        })
    }
    
    @IBAction func connectPushed(_ sender: Any) {
        if isConnected {
            tService.stop()
        } else if isLoading {
        
        } else {
            tService.start(ipAdress: ipField.text != nil ? ipField.text! : "", port: portField.text != nil ? portField.text! : "", magnetometer: magnetometerToggle.isOn, cvc: self)
        }
    }
    
    func setLoading() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.isConnected = false
            self.statusLabel.text = "Loading..."
            self.statusLabel.textColor = .none
            self.ipField.isEnabled = false
            self.portField.isEnabled = false
            self.magnetometerToggle.isEnabled = false
            self.connectButton.isEnabled = false
            self.connectButton.setTitle("Connect", for: .disabled)
            self.connectButton.setTitle("Connect", for: .focused)
            self.connectButton.setTitle("Connect", for: .normal)
            self.connectButton.setTitle("Connect", for: .selected)
            self.discoverButton.isEnabled = false
            self.loggingTextView.text = ""
            self.loadingIndicator.startAnimating()
        }
    }
    
    func setConnected() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isConnected = true
            self.statusLabel.text = "Connected"
            self.statusLabel.textColor = .green
            self.ipField.isEnabled = false
            self.portField.isEnabled = false
            self.magnetometerToggle.isEnabled = false
            self.connectButton.isEnabled = true
            self.connectButton.titleLabel!.text = "Disconnect"
            self.connectButton.setTitle("Disconnect", for: .disabled)
            self.connectButton.setTitle("Disconnect", for: .focused)
            self.connectButton.setTitle("Disconnect", for: .normal)
            self.connectButton.setTitle("Disconnect", for: .selected)
            self.discoverButton.isEnabled = false
            self.loadingIndicator.stopAnimating()
        }
    }
    
    func setUnconnected() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isConnected = false
            self.statusLabel.text = "Not Connected"
            self.statusLabel.textColor = .gray
            self.ipField.isEnabled = true
            self.portField.isEnabled = true
            self.magnetometerToggle.isEnabled = true
            self.connectButton.isEnabled = true
            self.connectButton.setTitle("Connect", for: .disabled)
            self.connectButton.setTitle("Connect", for: .focused)
            self.connectButton.setTitle("Connect", for: .normal)
            self.connectButton.setTitle("Connect", for: .selected)
            self.discoverButton.isEnabled = true
            self.loadingIndicator.stopAnimating()
        }
    }
    
    func setMagnometerToggle(use: Bool) {
        DispatchQueue.main.async {
            self.magnetometerToggle.isOn = use
        }
    }
    
    func updateLogs(text: String) {
        DispatchQueue.main.async {
            self.loggingTextView.text = text
            let range = NSMakeRange(self.loggingTextView.text.count - 1, 0)
            self.loggingTextView.scrollRangeToVisible(range)
        }
    }
}
