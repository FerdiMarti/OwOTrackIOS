//
//  ScreenDimmer.swift
//  OwOTrack
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

//the screen's brightness: UIScreen in the app, a fake in the tests
protocol AdjustableBrightness: AnyObject {
    var brightness: CGFloat { get set }
}

extension UIScreen: AdjustableBrightness {}

//while connected the iPhone doesn't lock automatically, so the screen would stay at full brightness for the whole session.
//this dims it (not black) after 30 s without a touch, and brightens it back on the next touch, when the connection
//ends or when the app leaves the foreground. While dimmed, an overlay takes the touch that brightens the screen,
//so brushing against the dimmed screen doesn't press a button. Used on the main thread only
final class ScreenDimmer: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    static let dimmedBrightness: CGFloat = 0.1

    @Published private(set) var isDimmed = false
    @Published private(set) var countdown: Int?     //seconds until dimming, during the last few seconds ("Dimming in 5…")

    let delay: TimeInterval
    private let countdownLength: TimeInterval
    private let fadeDuration: TimeInterval
    private let screen: () -> AdjustableBrightness?
    private var active = false
    private var idleTimer: Timer?
    private var countdownTimer: Timer?
    private var dimAt: Date?
    private var fadeTimer: Timer?
    private var userBrightness: CGFloat?        //the brightness before dimming, restored afterwards
    private var touchRecognizer: UIGestureRecognizer?

    init(delay: TimeInterval = 30, countdownLength: TimeInterval = 5, fadeDuration: TimeInterval = 0.5,
         screen: @escaping () -> AdjustableBrightness? = ScreenDimmer.appScreen) {
        self.delay = delay
        self.countdownLength = countdownLength
        self.fadeDuration = fadeDuration
        self.screen = screen
        super.init()
    }

    //on while connected and the app is in the foreground
    func setActive(_ active: Bool) {
        if active == self.active {
            return
        }
        self.active = active
        if active {
            watchTouches()
            restartIdleTimer()
        } else {
            idleTimer?.invalidate()
            idleTimer = nil
            stopCountdown()
            stopWatchingTouches()
            brighten()
        }
    }

    //any touch on the screen: brighten it if it's dimmed, and wait another 30 s
    func touched() {
        if !active {
            return
        }
        brighten()
        restartIdleTimer()
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        stopCountdown()
        let dimAt = Date().addingTimeInterval(delay)
        self.dimAt = dimAt
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dim()
        }
        //counts the last seconds down; checks often so the number changes on time
        let countdownStart = dimAt.addingTimeInterval(-min(countdownLength, delay))
        let timer = Timer(fire: countdownStart, interval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func updateCountdown() {
        guard let dimAt = dimAt else {
            return
        }
        let remaining = dimAt.timeIntervalSinceNow
        let seconds = remaining > 0 ? Int(remaining.rounded(.up)) : nil
        if countdown != seconds {
            countdown = seconds
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        dimAt = nil
        if countdown != nil {
            countdown = nil
        }
    }

    private func dim() {
        stopCountdown()
        guard active, !isDimmed, let screen = screen() else {
            return
        }
        let brightness = screen.brightness
        if brightness <= ScreenDimmer.dimmedBrightness {
            return      //already darker than that: leave it, and let touches through
        }
        userBrightness = brightness
        isDimmed = true
        fade(screen, from: brightness, to: ScreenDimmer.dimmedBrightness)
    }

    private func brighten() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if !isDimmed {
            return
        }
        isDimmed = false
        if let brightness = userBrightness {
            screen()?.brightness = brightness
        }
        userBrightness = nil
    }

    //lowers the brightness gradually like iOS does, instead of in one jump
    private func fade(_ screen: AdjustableBrightness, from start: CGFloat, to end: CGFloat) {
        let stepDuration: TimeInterval = 0.05
        let steps = Int(fadeDuration / stepDuration)
        if steps < 2 {
            screen.brightness = end
            return
        }
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            step += 1
            screen.brightness = step >= steps ? end : start + (end - start) * CGFloat(step) / CGFloat(steps)
            if step >= steps {
                timer.invalidate()
                self?.fadeTimer = nil
            }
        }
    }

    // MARK: touches

    //a recognizer on the window sees every touch without taking it away from the views
    private func watchTouches() {
        guard touchRecognizer == nil, let window = ScreenDimmer.appWindow() else {
            return
        }
        let recognizer = TouchDownRecognizer { [weak self] in
            self?.touched()
        }
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        touchRecognizer = recognizer
    }

    private func stopWatchingTouches() {
        if let recognizer = touchRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        touchRecognizer = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    static func appWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    static func appScreen() -> AdjustableBrightness? {
        return appWindow()?.windowScene?.screen
    }
}

//reports each touch as it begins, then fails right away, so it never gets in the way of other gestures
private final class TouchDownRecognizer: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}
