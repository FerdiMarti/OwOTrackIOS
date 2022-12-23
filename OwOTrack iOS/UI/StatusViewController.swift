//
//  StatusViewController.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 02.05.21.
//

import UIKit

class StatusViewController: UIViewController {

    @IBOutlet weak var motionAvailable: UILabel!
    @IBOutlet weak var accelAvailable: UILabel!
    @IBOutlet weak var gyroAvailable: UILabel!
    @IBOutlet weak var magnetometerAvailable: UILabel!
    
    let sensorHandler = GyroHandler.getInstance()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if sensorHandler.motionAvailable {
            motionAvailable.text = "Available"
            motionAvailable.textColor = UIColor.green
        } else {
            motionAvailable.text = "Unavailable"
            motionAvailable.textColor = UIColor.red
        }
        
        if sensorHandler.accelerometerAvailable {
            accelAvailable.text = "Available"
            accelAvailable.textColor = UIColor.green
        } else {
            accelAvailable.text = "Unavailable"
            accelAvailable.textColor = UIColor.red
        }
        
        if sensorHandler.gyroAvailable {
            gyroAvailable.text = "Available"
            gyroAvailable.textColor = UIColor.green
        } else {
            gyroAvailable.text = "Unavailable"
            gyroAvailable.textColor = UIColor.red
        }
        
        if sensorHandler.magnetometerAvailable {
            magnetometerAvailable.text = "Available"
            magnetometerAvailable.textColor = UIColor.green
        } else {
            magnetometerAvailable.text = "Unavailable"
            magnetometerAvailable.textColor = UIColor.red
        }
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
