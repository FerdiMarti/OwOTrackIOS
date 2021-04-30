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
    @State var useMagnetometer = true
    
    let defaults = UserDefaults.standard
    let sensorHandler = GyroHandler.getInstance()
    let logger = Logger.getInstance()
    let tService = TrackingService()
    
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
                            ProgressView().padding(.trailing, 5)
                            Text("Loading...")
                        }.padding(.bottom, 5)
                        TextField("Ip Adress", text: $ipAdress)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(true)
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(true).padding(.bottom, 5)
                        Toggle("Use Magnetometer", isOn: $useMagnetometer).disabled(true).padding(.bottom, 5)
                        Button(action: {}, label: {Text("Connect")}).disabled(true).padding(.bottom, 5).padding(.top, 5)
                    } else if connected {
                        Text("Connected").foregroundColor(.green).padding(.bottom, 5)
                        TextField("Ip Adress", text: $ipAdress)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(true)
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(true).padding(.bottom, 5)
                        Toggle("Use Magnetometer", isOn: $useMagnetometer).disabled(true).padding(.bottom, 5)
                        Button(action: {
                            tService.stop()
                        }, label: {
                            Text("Disconnect")
                        }).padding(.bottom, 5)
                    } else {
                        Text("Not Connected").foregroundColor(.gray).padding(.bottom, 5)
                        TextField("Ip Adress", text: $ipAdress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).padding(.bottom, 5)
                        Toggle("Use Magnetometer", isOn: $useMagnetometer).padding(.bottom, 5)
                        Button(action: {
                            tService.start(ipAdress: ipAdress, port: port, magnetometer: useMagnetometer, cView: self)
                        }, label: {
                            Text("Connect")
                        })
                        .padding(.bottom, 5)
                    }
                    Spacer()
                    ScrollView {
                        Text(logger.get()).padding()
                    }
                }
                .padding()
                .navigationTitle("Connect")
            }
            .tabItem {
                Image(systemName: "wifi")
                Text("Connect")
            }
            
            //ThirdTab
            NavigationView {
                VStack {
                    Text("Deactivating the magnetometer can improve latency, phone battery life and fix issues with nearby magnets. It will however increase yaw drift.")
                }
                .padding()
                .navigationTitle("Information")
            }
            .tabItem {
                Image(systemName: "info.circle")
                Text("Information")
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
            if let useMagnTemp = defaults.object(forKey: "useM") as? Bool {
                useMagnetometer = useMagnTemp
            } else {
                self.defaults.set(useMagnetometer, forKey: "useM")
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
