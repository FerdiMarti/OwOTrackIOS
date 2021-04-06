//
//  ContentView.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import SwiftUI

struct ContentView: View {
    @State var ipAdress: String = "10.211.55.3"
    @State var port: String = "6969"
    @State var loading = false
    @State var connected = false
    
    let defaults = UserDefaults.standard
    let sensorHandler = GyroHandler.getInstance()
    let logger = Logger.getInstance()
    
    var body: some View {
        TabView {
            //First Tab
            NavigationView {
                VStack {
                    Text("Motion Sensor").padding(.top, 5)
                    if sensorHandler.motionAvailable {
                        Text("Available").foregroundColor(.green).padding(.bottom, 5)
                    } else {
                        Text("Unavailable").foregroundColor(.red).padding(.bottom, 5)
                    }
                    
                    Text("Accelerometer").padding(.top, 5)
                    if sensorHandler.accelerometerAvailable {
                        Text("Available").foregroundColor(.green).padding(.bottom, 5)
                    } else {
                        Text("Unavailable").foregroundColor(.red).padding(.bottom, 5)
                    }
                    
                    Text("Gyrosensor").padding(.top, 5)
                    if sensorHandler.gyroAvailable {
                        Text("Available").foregroundColor(.green).padding(.bottom, 5)
                    } else {
                        Text("Unavailable").foregroundColor(.red).padding(.bottom, 5)
                    }
                    
                    Text("Magnetometer").padding(.top, 5)
                    if sensorHandler.magnetometerAvailable {
                        Text("Available").foregroundColor(.green).padding(.bottom, 5)
                    } else {
                        Text("Unavailable").foregroundColor(.red).padding(.bottom, 5)
                    }
                }
                .navigationTitle("Sensor Status")
            }
            .tabItem {
                Image(systemName: "iphone.radiowaves.left.and.right")
                Text("Status")
            }
            
            //Second Tab
            NavigationView {
                VStack {
                    if loading {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                        }
                        Text(ipAdress)
                        Text(port)
                    } else if connected {
                        Text("Connected").foregroundColor(.green)
                        Text(ipAdress)
                        Text(port)
                    } else {
                        TextField("Ip Adress", text: $ipAdress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("Not Connected").foregroundColor(.gray)
                    }
                    Button(action: {
                        let tService = TrackingService(ipAdress: ipAdress, port: port, cView: self)
                        tService.start()
                    }, label: {
                        Image(systemName: "link")
                        Text("Connect")
                    })
                    .disabled(loading || connected)
                    Spacer()
                    Text(logger.get())
                }
                .padding()
                .navigationTitle("Connect")
            }
            .tabItem {
                Image(systemName: "wifi")
                Text("Connect")
            }
        }
        .onAppear {
            if let ipTemp = defaults.object(forKey: "ip") as? String {
                ipAdress = ipTemp
            } else {
                ipAdress = "192.168.0.1"
                self.defaults.set(ipAdress, forKey: "ip")
            }
            if let portTemp = defaults.object(forKey: "port") as? String {
                port = portTemp
            } else {
                port = "6969"
                self.defaults.set(port, forKey: "port")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
        }
    }
}
