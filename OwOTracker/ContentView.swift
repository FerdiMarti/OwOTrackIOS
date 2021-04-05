//
//  ContentView.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import SwiftUI

struct ContentView: View {
    @State var ipadress: String = "10.211.55.3"
    @State var port: String = "6969"
    //@State var ipadress: String = "10.37.129.2"
    //@State var port: String = "57453"
    
    var body: some View {
        TabView {
            //First Tab
            NavigationView {
                VStack {
                    Text("sdfsdf")
                    Text("sdfsdfsd")
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
                    TextField("Ip Adress", text: $ipadress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Port", text: $port)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: {
                        let client = UDPGyroProviderClient(host: ipadress, port: port)
                        client.connectToUDP()
                        client.handshake()
                        let handler = GyroHandler.getInstance(client: client)
                    }, label: {
                        Image(systemName: "link")
                        Text("Connect")
                    })
                }
                .padding()
                .navigationTitle("Connect")
            }
            .tabItem {
                Image(systemName: "wifi")
                Text("Connect")
            }
            
            //Third Tab
            NavigationView {
                Text("Log")
                    .navigationTitle("Event Log")
            }
            .tabItem {
                Image(systemName: "doc.fill")
                Text("Log")
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
