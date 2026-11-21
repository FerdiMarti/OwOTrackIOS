//
//  VolumeButtonPositions.swift
//  OwOTrack
//
//  Where the volume buttons are on each iPhone model, for the labels next to them on the screen.
//

import UIKit

//the centers of the volume buttons, as a share of the screen height, from the top of the screen
struct VolumeButtonPositions: Equatable {
    let up: CGFloat
    let down: CGFloat

    //for models that aren't in the table yet (newer ones): fits the iPhone 15 to 17
    static let estimate = VolumeButtonPositions(up: 0.315, down: 0.415)

    init(up: CGFloat, down: CGFloat) {
        self.up = up
        self.down = down
    }

    //from a model's measurements in mm: where the display's active area starts below the top of the phone,
    //how high it is, and how far below the top of the phone the centers of the volume buttons are
    init(displayTop: Double, displayHeight: Double, volumeUp: Double, volumeDown: Double) {
        up = CGFloat((volumeUp - displayTop) / displayHeight)
        down = CGFloat((volumeDown - displayTop) / displayHeight)
    }

    //the positions on this iPhone; nil if its volume buttons aren't on the side
    static let current = forModel(deviceModel)

    static func forModel(_ identifier: String) -> VolumeButtonPositions? {
        if modelsWithButtonsOnTop.contains(identifier) {
            return nil
        }
        return models.first { $0.identifiers.contains(identifier) }?.positions ?? estimate
    }

    //the iPhone Duo (a foldable) has its volume buttons on the top edge, so the screen explains them in a line of text instead
    static let modelsWithButtonsOnTop: Set<String> = ["iPhone19,4"]

    //the model identifier, e.g. "iPhone18,3" for an iPhone 17. In the simulator, the simulated model's
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    struct Model {
        let name: String
        let identifiers: [String]
        let positions: VolumeButtonPositions
    }

    //measurements in mm from Apple's dimensional drawings for accessory makers (developer.apple.com/accessories/dimensional-drawings),
    //read in November 2026: the top of the display's active area (the "exterior of housing to display active area" note,
    //or "to active area" on older drawings), its height, and the centers of the volume buttons in the side view.
    //Identifiers: the community list at gist.github.com/adamawolf/3048717, and Xcode's simulator profiles for the iPhone 18 Pro models.
    //The iPhone 6s, 7 and 8 have no drawing anymore; they share the design of the iPhone SE (2nd generation), whose drawing
    //also covers the 3rd generation. The other older models are no longer on that page either: their measurements come from
    //the drawings in Apple's Accessory Design Guidelines of 2021-09-28 (chapter 44, archived at web.archive.org).
    //The first iPhone SE's drawing shows the display's 90.39 mm outline, 16.72 mm from the top and bottom: its active area
    //(1136 pixels at 326 ppi, 88.51 mm) is centered in it. The 7 Plus uses the 8 Plus drawing (same housing, cases fit both),
    //the XS the X drawing (same measurements as the XS Max's top). Future models use the estimate
    static let models: [Model] = [
        Model(name: "iPhone SE (1st generation)", identifiers: ["iPhone8,4"],
              positions: VolumeButtonPositions(displayTop: 17.66, displayHeight: 88.51, volumeUp: 30.93, volumeDown: 41.22)),
        Model(name: "iPhone 6s Plus", identifiers: ["iPhone8,2"],
              positions: VolumeButtonPositions(displayTop: 18.34, displayHeight: 121.54, volumeUp: 35.55, volumeDown: 48.16)),
        Model(name: "iPhone 7 Plus, 8 Plus", identifiers: ["iPhone9,2", "iPhone9,4", "iPhone10,2", "iPhone10,5"],
              positions: VolumeButtonPositions(displayTop: 18.42, displayHeight: 121.54, volumeUp: 35.63, volumeDown: 48.24)),
        Model(name: "iPhone X, XS", identifiers: ["iPhone10,3", "iPhone10,6", "iPhone11,2"],
              positions: VolumeButtonPositions(displayTop: 3.91, displayHeight: 135.75, volumeUp: 34.83, volumeDown: 47.94)),
        Model(name: "iPhone XS Max", identifiers: ["iPhone11,4", "iPhone11,6"],
              positions: VolumeButtonPositions(displayTop: 3.91, displayHeight: 149.71, volumeUp: 34.84, volumeDown: 47.94)),
        Model(name: "iPhone XR, 11", identifiers: ["iPhone11,8", "iPhone12,1"],
              positions: VolumeButtonPositions(displayTop: 5.57, displayHeight: 139.78, volumeUp: 36.09, volumeDown: 49.20)),
        Model(name: "iPhone 11 Pro", identifiers: ["iPhone12,3"],
              positions: VolumeButtonPositions(displayTop: 4.52, displayHeight: 134.95, volumeUp: 37.84, volumeDown: 51.37)),
        Model(name: "iPhone 11 Pro Max", identifiers: ["iPhone12,5"],
              positions: VolumeButtonPositions(displayTop: 4.52, displayHeight: 148.91, volumeUp: 37.84, volumeDown: 51.37)),
        Model(name: "iPhone 6s, 7 and 8", identifiers: ["iPhone8,1", "iPhone9,1", "iPhone9,3", "iPhone10,1", "iPhone10,4"],
              positions: VolumeButtonPositions(displayTop: 17.19, displayHeight: 104.05, volumeUp: 34.56, volumeDown: 47.17)),
        Model(name: "iPhone SE (2nd and 3rd generation)", identifiers: ["iPhone12,8", "iPhone14,6"],
              positions: VolumeButtonPositions(displayTop: 17.19, displayHeight: 104.05, volumeUp: 34.56, volumeDown: 47.17)),
        Model(name: "iPhone 12 mini", identifiers: ["iPhone13,1"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 124.96, volumeUp: 36.68, volumeDown: 50.68)),
        Model(name: "iPhone 12, 12 Pro", identifiers: ["iPhone13,2", "iPhone13,3"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 139.77, volumeUp: 39.31, volumeDown: 53.31)),
        Model(name: "iPhone 12 Pro Max", identifiers: ["iPhone13,4"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 153.90, volumeUp: 46.65, volumeDown: 60.65)),
        Model(name: "iPhone 13 mini", identifiers: ["iPhone14,4"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 124.96, volumeUp: 36.68, volumeDown: 50.68)),
        Model(name: "iPhone 13, 13 Pro", identifiers: ["iPhone14,5", "iPhone14,2"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 139.77, volumeUp: 45.53, volumeDown: 59.53)),
        Model(name: "iPhone 13 Pro Max", identifiers: ["iPhone14,3"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 153.90, volumeUp: 45.53, volumeDown: 59.53)),
        Model(name: "iPhone 14", identifiers: ["iPhone14,7"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 139.77, volumeUp: 45.43, volumeDown: 59.63)),
        Model(name: "iPhone 14 Plus", identifiers: ["iPhone14,8"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 153.90, volumeUp: 45.43, volumeDown: 59.63)),
        Model(name: "iPhone 14 Pro", identifiers: ["iPhone15,2"],
              positions: VolumeButtonPositions(displayTop: 3.19, displayHeight: 141.09, volumeUp: 44.59, volumeDown: 58.79)),
        Model(name: "iPhone 14 Pro Max", identifiers: ["iPhone15,3"],
              positions: VolumeButtonPositions(displayTop: 3.19, displayHeight: 154.34, volumeUp: 44.59, volumeDown: 58.79)),
        Model(name: "iPhone 15", identifiers: ["iPhone15,4"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 141.09, volumeUp: 46.27, volumeDown: 60.47)),
        Model(name: "iPhone 15 Plus", identifiers: ["iPhone15,5"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 154.34, volumeUp: 45.39, volumeDown: 59.59)),
        Model(name: "iPhone 15 Pro", identifiers: ["iPhone16,1"],
              positions: VolumeButtonPositions(displayTop: 2.76, displayHeight: 141.09, volumeUp: 45.22, volumeDown: 59.42)),
        Model(name: "iPhone 15 Pro Max", identifiers: ["iPhone16,2"],
              positions: VolumeButtonPositions(displayTop: 2.76, displayHeight: 154.34, volumeUp: 45.22, volumeDown: 59.42)),
        Model(name: "iPhone 16", identifiers: ["iPhone17,3"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 141.09, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 16 Plus", identifiers: ["iPhone17,4"],
              positions: VolumeButtonPositions(displayTop: 3.27, displayHeight: 154.34, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 16 Pro", identifiers: ["iPhone17,1"],
              positions: VolumeButtonPositions(displayTop: 2.44, displayHeight: 144.79, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 16 Pro Max", identifiers: ["iPhone17,2"],
              positions: VolumeButtonPositions(displayTop: 2.36, displayHeight: 158.31, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 16e, 17e", identifiers: ["iPhone17,5", "iPhone18,5"],
              positions: VolumeButtonPositions(displayTop: 3.47, displayHeight: 139.77, volumeUp: 45.43, volumeDown: 59.63)),
        Model(name: "iPhone 17", identifiers: ["iPhone18,3"],
              positions: VolumeButtonPositions(displayTop: 2.44, displayHeight: 144.79, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 17 Pro", identifiers: ["iPhone18,1"],
              positions: VolumeButtonPositions(displayTop: 2.64, displayHeight: 144.73, volumeUp: 48.43, volumeDown: 62.63)),
        Model(name: "iPhone 17 Pro Max", identifiers: ["iPhone18,2"],
              positions: VolumeButtonPositions(displayTop: 2.56, displayHeight: 158.31, volumeUp: 48.43, volumeDown: 62.63)),
        Model(name: "iPhone Air", identifiers: ["iPhone18,4"],
              positions: VolumeButtonPositions(displayTop: 2.58, displayHeight: 151.03, volumeUp: 48.23, volumeDown: 62.43)),
        Model(name: "iPhone 18 Pro", identifiers: ["iPhone19,2"],
              positions: VolumeButtonPositions(displayTop: 2.64, displayHeight: 144.73, volumeUp: 48.43, volumeDown: 62.63)),
        Model(name: "iPhone 18 Pro Max", identifiers: ["iPhone19,3"],
              positions: VolumeButtonPositions(displayTop: 2.56, displayHeight: 158.31, volumeUp: 48.43, volumeDown: 62.63)),
    ]
}
