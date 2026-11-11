import CoreGraphics
import Foundation
import os

final class LidLogo {
    let bridge = LogoBridge()
    private var originalMode: Int?
    private var direction: Bool?
    private var holding = false
    private var lastChange = -Double.infinity
    // Each level read is a synchronous round trip to corebrightnessd. Once the logo has settled
    // on an unchanged target, re-read it only every `settledRecheck` seconds to catch drift.
    private var settledTarget: Double?
    private var nextSettledCheck = 0.0
    private let settledRecheck = 0.5
    var isSettled: Bool { settledTarget != nil }
    private(set) var measuredLevel = 0.0
    var onRiseFromDark: (() -> Void)?

    var available: Bool { bridge.mode >= 0 && bridge.level.isFinite }
    var awake: Bool {
        let screen = CGMainDisplayID()
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return CGDisplayIsBuiltin(screen) != 0 && CGDisplayIsAsleep(screen) == 0
        }
        return displays.prefix(Int(count)).contains {
            CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0
        }
    }

    func takeControl() -> Bool {
        guard originalMode == nil else { return true }
        let mode = bridge.mode
        guard mode >= 0, bridge.level.isFinite else {
            Logger.hardware.error("Couldn't read the logo state, so Lidglow didn't take control")
            return false
        }
        if mode == 0 && !bridge.enableLogo(true) {
            Logger.hardware.error("Couldn't enable the logo backlight")
            return false
        }
        Logger.hardware.notice("Took control of the logo (backlight mode \(mode))")
        originalMode = mode
        direction = nil
        holding = false
        lastChange = -.infinity
        settledTarget = nil
        return true
    }

    func restore() {
        guard let mode = originalMode else { return }
        originalMode = nil
        settledTarget = nil
        if direction != nil {
            let displayAwake = awake && !bridge.lidClosed
            if displayAwake {
                if direction != false { _ = bridge.fade(towardLight: false, duration: 3600, displayAwake: true) }
                _ = bridge.fade(towardLight: true, duration: 0, displayAwake: true)
            } else {
                if direction == false { _ = bridge.fade(towardLight: true, duration: 3600, displayAwake: false) }
                _ = bridge.fade(towardLight: false, duration: 0, displayAwake: false)
            }
        }
        if mode == 0 { _ = bridge.enableLogo(false) }
        Logger.hardware.notice("Handed the logo back to macOS (backlight mode \(mode))")
        direction = nil
        holding = false
    }

    func follow(_ target: Double, now: Double, rise: Double, fall: Double, tolerance: Double = 0.045) -> Bool {
        guard originalMode != nil else { return false }
        if target == settledTarget && now < nextSettledCheck { return true }
        settledTarget = nil
        let level = bridge.level
        guard level.isFinite else { return false }
        measuredLevel = min(1, max(0, level))
        let delta = target - level
        if abs(delta) <= tolerance || (target == 0 && direction == false && !holding) {
            let needsHold = !holding && target > 0 && target < 1 && direction != nil
            if needsHold, let direction, now - lastChange > 0.045 {
                return command(!direction, duration: 3600, hold: true, now: now)
            }
            let reachedTarget = target == 0 ? level <= 0.003 : abs(delta) <= tolerance
            if !needsHold && reachedTarget {
                settledTarget = target
                nextSettledCheck = now + settledRecheck
            }
            return true
        }

        let rising = delta > 0
        if direction == rising && !holding { return true }
        guard now - lastChange > 0.065 else { return true }
        if direction == nil || direction == rising {
            guard command(!rising, duration: 3600, hold: true, now: now) else { return false }
        }

        // Calibrate the hardware spring against the fraction of the full ramp we need.
        let fraction = min(1, abs(delta) / max(0.001, rising ? 1 - level : level))
        var low = 0.0
        var high = 1.0
        for _ in 0..<10 {
            let midpoint = (low + high) / 2
            let x = 6.51 * midpoint
            if 1 - (1 + x) * exp(-x) < fraction { low = midpoint } else { high = midpoint }
        }
        let duration = min(3, (rising ? rise : fall) / max(0.05, high))
        if rising && level < 0.04 { onRiseFromDark?() }
        return command(rising, duration: duration, hold: false, now: now)
    }

    private func command(_ lit: Bool, duration: Double, hold: Bool, now: Double) -> Bool {
        guard bridge.fade(towardLight: lit, duration: duration, displayAwake: true) else { return false }
        direction = lit
        holding = hold
        lastChange = now
        return true
    }
}
