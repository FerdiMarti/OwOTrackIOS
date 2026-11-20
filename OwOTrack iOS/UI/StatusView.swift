//
//  StatusView.swift
//  OwOTrack
//

import SwiftUI

//which motion sensors the device has
struct StatusView: View {
    private let sensors = GyroHandler.getInstance()

    var body: some View {
        VStack(spacing: 8) {
            sensor("Motion Sensor", available: sensors.motionAvailable)
            sensor("Accelerometer", available: sensors.accelerometerAvailable)
            sensor("Gyrosensor", available: sensors.gyroAvailable)
            sensor("Magnetometer", available: sensors.magnetometerAvailable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sensor Status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sensor(_ name: String, available: Bool) -> some View {
        VStack(spacing: 0) {
            Text(name)
            Text(available ? "Available" : "Unavailable")
                .foregroundColor(available ? .green : .red)
        }
    }
}
