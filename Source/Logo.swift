import CoreGraphics
import Foundation

final class LidLogo {
    let bridge = LogoBridge()
    private var originalMode: Int?
    private var direction: Bool?
    private var holding = false
    private var lastChange = -Double.infinity
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
        guard mode >= 0, bridge.level.isFinite else { return false }
        if mode == 0 && !bridge.enableLogo(true) { return false }
        originalMode = mode
        direction = nil
        holding = false
        lastChange = -.infinity
        return true
    }

    func restore() {
        guard let mode = originalMode else { return }
        originalMode = nil
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
        direction = nil
        holding = false
    }

    func follow(_ target: Double, now: Double, rise: Double, fall: Double, tolerance: Double = 0.045) -> Bool {
        guard originalMode != nil else { return false }
        let level = bridge.level
        guard level.isFinite else { return false }
        let delta = target - level
        if abs(delta) <= tolerance || (target == 0 && direction == false && !holding) {
            if !holding, target > 0, target < 1, let direction, now - lastChange > 0.045 {
                return command(!direction, duration: 3600, hold: true, now: now)
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
