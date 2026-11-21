//
//  ScreenDimmerTests.swift
//  OwOTrackTests
//
//  Dimming the screen while connected, with a fake screen and a 0.3 s delay instead of 30 s.
//

import Foundation
import Testing
@testable import OwOTrack_iOS

final class FakeScreen: AdjustableBrightness {
    var brightness: CGFloat

    init(brightness: CGFloat) {
        self.brightness = brightness
    }
}

extension OwOTrackTests {
    @Suite("Dimming the screen")
    @MainActor
    struct Dimming {
        static let delay: TimeInterval = 0.3

        func makeDimmer(brightness: CGFloat = 0.8, fade: TimeInterval = 0) -> (ScreenDimmer, FakeScreen) {
            let screen = FakeScreen(brightness: brightness)
            return (ScreenDimmer(delay: Dimming.delay, fadeDuration: fade, screen: { screen }), screen)
        }

        @Test("dims after the delay without a touch, not to black")
        func dims() async {
            let (dimmer, screen) = makeDimmer()
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay / 2)
            #expect(!dimmer.isDimmed)
            #expect(screen.brightness == 0.8)
            await pause(Dimming.delay)
            #expect(dimmer.isDimmed)
            #expect(screen.brightness == ScreenDimmer.dimmedBrightness)
            #expect(screen.brightness > 0)
        }

        @Test("fades down gradually")
        func fades() async {
            let (dimmer, screen) = makeDimmer(fade: 0.5)
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay + 0.2)
            #expect(screen.brightness < 0.8)
            #expect(screen.brightness > ScreenDimmer.dimmedBrightness)
            await pause(0.5)
            #expect(screen.brightness == ScreenDimmer.dimmedBrightness)
        }

        @Test("a touch brightens the screen back to the user's brightness and starts the wait again")
        func touchBrightens() async {
            let (dimmer, screen) = makeDimmer()
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay + 0.1)
            #expect(dimmer.isDimmed)
            dimmer.touched()
            #expect(!dimmer.isDimmed)
            #expect(screen.brightness == 0.8)
            await pause(Dimming.delay / 2)
            #expect(!dimmer.isDimmed)
            await pause(Dimming.delay)
            #expect(dimmer.isDimmed)
        }

        @Test("a touch while fading stops the fade and brightens")
        func touchWhileFading() async {
            let (dimmer, screen) = makeDimmer(fade: 0.5)
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay + 0.15)
            #expect(screen.brightness < 0.8)
            dimmer.touched()
            #expect(screen.brightness == 0.8)
            await pause(0.1)    //the fade would have changed it by now, the next dimming is still 0.2 s away
            #expect(screen.brightness == 0.8)
        }

        @Test("touches keep the screen bright")
        func touchesPostpone() async {
            let (dimmer, _) = makeDimmer()
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            for _ in 0..<4 {
                await pause(Dimming.delay * 0.6)
                dimmer.touched()
            }
            #expect(!dimmer.isDimmed)
        }

        @Test("on while this iPhone or the watch through it tracks (also while reconnecting), and only in the foreground")
        func switchedOn() async {
            #expect(ScreenDimmer.shouldBeActive(tracking: true, relaying: false, inForeground: true))
            #expect(ScreenDimmer.shouldBeActive(tracking: false, relaying: true, inForeground: true))
            #expect(!ScreenDimmer.shouldBeActive(tracking: true, relaying: true, inForeground: false))
            #expect(!ScreenDimmer.shouldBeActive(tracking: false, relaying: false, inForeground: true))
            //what counts as tracking on the connect screen (the app passes canDisconnect)
            let model = ConnectionModel(service: RecordingService(), sharing: nil, finder: FakeFinder(result: ServerSearchResult()))
            model.setConnected()
            #expect(await waitUntil { model.isConnected && model.canDisconnect })
            model.setReconnecting(until: Date().addingTimeInterval(60))
            #expect(await waitUntil { model.isReconnecting && model.canDisconnect })
            model.setFailed("Couldn't reconnect")
            #expect(await waitUntil { !model.canDisconnect })
            model.setLoading()
            #expect(await waitUntil { model.isConnecting && !model.canDisconnect })
            model.setUnconnected()
            #expect(await waitUntil { model.status == .notConnected && !model.canDisconnect })
        }

        @Test("never dims while not connected")
        func inactive() async {
            let (dimmer, screen) = makeDimmer()
            await pause(Dimming.delay * 2)
            dimmer.touched()
            await pause(Dimming.delay * 2)
            #expect(!dimmer.isDimmed)
            #expect(screen.brightness == 0.8)
        }

        @Test("brightens when the connection ends or the app leaves the foreground, and stays bright")
        func deactivating() async {
            let (dimmer, screen) = makeDimmer()
            dimmer.setActive(true)
            await pause(Dimming.delay + 0.1)
            #expect(dimmer.isDimmed)
            dimmer.setActive(false)
            #expect(!dimmer.isDimmed)
            #expect(dimmer.countdown == nil)
            #expect(screen.brightness == 0.8)
            await pause(Dimming.delay * 2)
            #expect(screen.brightness == 0.8)
            #expect(dimmer.countdown == nil)
        }

        @Test("counts down only the last seconds, and a touch starts the wait over")
        func countdown() async {
            let screen = FakeScreen(brightness: 0.8)
            let dimmer = ScreenDimmer(delay: 1.2, countdownLength: 0.6, fadeDuration: 0, screen: { screen })
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(0.3)
            #expect(dimmer.countdown == nil)    //not in the last 0.6 s yet
            await pause(0.5)
            #expect(dimmer.countdown == 1)
            dimmer.touched()
            #expect(dimmer.countdown == nil)
            await pause(1.0)
            #expect(dimmer.countdown == 1)
            await pause(0.4)
            #expect(dimmer.isDimmed)
            #expect(dimmer.countdown == nil)
        }

        @Test("counts down whole seconds: 3, 2, 1")
        func countdownSeconds() async {
            let screen = FakeScreen(brightness: 0.8)
            let dimmer = ScreenDimmer(delay: 2.5, countdownLength: 5, fadeDuration: 0, screen: { screen })
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            var shown: [Int] = []
            for _ in 0..<28 {
                if let seconds = dimmer.countdown, shown.last != seconds {
                    shown.append(seconds)
                }
                await pause(0.1)
            }
            #expect(shown == [3, 2, 1])
            #expect(dimmer.isDimmed)
        }

        @Test("a screen already darker than the dimmed level is left alone, and touches go through")
        func alreadyDark() async {
            let (dimmer, screen) = makeDimmer(brightness: 0.05)
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay * 2)
            #expect(!dimmer.isDimmed)
            #expect(screen.brightness == 0.05)
        }

        @Test("picks up a brightness the user changed since the last dimming")
        func userChangedBrightness() async {
            let (dimmer, screen) = makeDimmer()
            defer { dimmer.setActive(false) }
            dimmer.setActive(true)
            await pause(Dimming.delay + 0.1)
            dimmer.touched()
            screen.brightness = 0.5     //e.g. in Control Center
            await pause(Dimming.delay + 0.1)
            #expect(dimmer.isDimmed)
            dimmer.touched()
            #expect(screen.brightness == 0.5)
        }
    }
}
