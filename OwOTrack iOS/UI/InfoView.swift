//
//  InfoView.swift
//  OwOTrack
//

import SwiftUI

//help text, unchanged from the old Information tab
struct InfoView: View {
    var body: some View {
        ScrollView {
            Text(InfoView.text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .navigationTitle("Information")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let text = """
        It is recommended to only use SlimeVR server since the OwOTrack driver is no longer maintained.

        ----

        The "discover" feature tries to find the ip address of a running OwOTrack driver automatically. It only works with the OwOTrack Driver and not with SlimeVR.

        ----

        Deactivating the magnetometer can improve latency, phone battery life and fix issues with nearby magnets. It will however increase yaw drift.

        When connected to SlimeVR, SlimeVR controls the magnetometer and the switch in the app follows: turn on "Use magnetometer on all IMU trackers that support it" in SlimeVR's settings, and "Allow magnetometer" in the tracker's settings. The switch in the app sets the starting value and controls the magnetometer when using the OwOTrack driver.

        ----

        Background Usage

        If you want the app to stay connected while running in the background or while the phone is turned off, you have to give the app permission to always use location data.
        Your location data will not be used by the developer or anyone else. It will never leave your device. Only the permission is required for the app to run in the background.
        If you deny the permission, the app will still work and stay connected as long as it is open.

        The app can not run in the background forever and might disconnect after 10 - 30 minutes depending on your circumstances. If you want to avoid this, leave the app open: while connected, the app keeps your iPhone from locking automatically.

        You can make the screen of your iPhone turn off by covering the sensor on the top of the phone (next to the camera). This will turn the screen off to save battery life and the app will stay connected.
        """
}
