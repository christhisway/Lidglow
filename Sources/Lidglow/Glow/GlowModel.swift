import AppKit
import Combine

final class GlowModel: ObservableObject {
    @Published private(set) var mode: GlowMode = .standard
    /// Whether Lidglow drives the logo. Off hands the logo back to macOS, which was System mode in 1.0.
    @Published private(set) var enabled = false
    @Published private(set) var level = 0.0
    @Published private(set) var status = "Checking lid hardware…"
    @Published private(set) var audioError = false
    @Published var brightness = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 0.82 {
        didSet {
            // The far left of the slider turns the logo off, so snap a near-zero drag to exactly zero.
            if brightness != 0 && brightness < 0.01 { brightness = 0 }
            UserDefaults.standard.set(brightness, forKey: "brightness")
            updateIcon()
            speedUp()
        }
    }
    @Published var sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }

    @Published var breatheSpeed = UserDefaults.standard.string(forKey: "breatheSpeed")
        .flatMap(BreatheSpeed.init(rawValue:)) ?? .normal {
        didSet {
            UserDefaults.standard.set(breatheSpeed.rawValue, forKey: "breatheSpeed")
            // Keep the current point in the breath and continue from it at the new speed, so the glow
            // doesn't jump.
            let now = ProcessInfo.processInfo.systemUptime
            phaseStart = now - (now - phaseStart) / oldValue.period * breatheSpeed.period
        }
    }

    @Published var idleGlow = UserDefaults.standard.bool(forKey: "idleGlow") {
        didSet { UserDefaults.standard.set(idleGlow, forKey: "idleGlow") }
    }
    @Published private var preferredIdleBrightness = UserDefaults.standard.object(forKey: "idleBrightness") as? Double {
        didSet { UserDefaults.standard.set(preferredIdleBrightness, forKey: "idleBrightness") }
    }

    /// Idle glow stays below 90% of the peak. The slider keeps a usable range even at zero brightness,
    /// and `tick()` applies the cap, so idle glow can never outshine the peak.
    var idleBrightnessRange: ClosedRange<Double> { 0.01...max(0.02, brightness * 0.90) }
    var idleBrightness: Double {
        get {
            let preferred = preferredIdleBrightness ?? min(0.12, brightness * 0.30)
            return min(idleBrightnessRange.upperBound, max(idleBrightnessRange.lowerBound, preferred))
        }
        set { preferredIdleBrightness = newValue }
    }

    private let logo = LidLogo()
    private let music = SystemMusic()
    private var timer: Timer?
    private var phaseStart = 0.0
    private var sessionActive = true
    private var displaysAwake = true
    private var hardwareCheck = 0.0
    private var mayRun = true
    private var lastSignal: Double?
    private var latestLevel = 0.0
    /// The preview only needs live levels while the panel is on screen. A hidden SwiftUI host
    /// still lays out on every change, which costs more than the glow loop itself in Music mode.
    @Published var panelVisible = false {
        didSet { if panelVisible && !oldValue { publishLevel(latestLevel) } }
    }
    var onIconChange: ((Bool) -> Void)?
    var onRiseFromDark: (() -> Void)? {
        didSet { logo.onRiseFromDark = onRiseFromDark }
    }

    init() {
        status = idleStatus
        let events: [(NSNotification.Name, Selector)] = [
            (NSWorkspace.screensDidSleepNotification, #selector(screenSleep)),
            (NSWorkspace.screensDidWakeNotification, #selector(screenWake)),
            (NSWorkspace.willSleepNotification, #selector(screenSleep)),
            (NSWorkspace.didWakeNotification, #selector(screenWake)),
            (NSWorkspace.sessionDidResignActiveNotification, #selector(lockSession)),
            (NSWorkspace.sessionDidBecomeActiveNotification, #selector(unlockSession))
        ]
        for (event, action) in events {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: action, name: event, object: nil)
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(lockSession), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(unlockSession), name: .init("com.apple.screenIsUnlocked"), object: nil)
        music.onSound = { [weak self] in self?.speedUp() }
    }

    var hasHardware: Bool { logo.bridge.hardwarePresent }
    private var idleStatus: String {
        if !hasHardware { return "Preview only · No controllable lid logo found" }
        return logo.available ? "macOS is managing the lid logo" : "Lid logo service unavailable"
    }

    private static let modeKey = "glowMode"
    private static let enabledKey = "glowEnabled"

    func restoreSelectedMode() {
        let defaults = UserDefaults.standard
        var saved = defaults.string(forKey: Self.modeKey)
        // Lidglow 1.0 saved System, Off, and Steady as modes. System is now the switch turned off,
        // and Off and Steady are both Standard, with Off at zero brightness.
        switch saved {
        case "System": defaults.set(false, forKey: Self.enabledKey); saved = nil
        case "Off": brightness = 0; saved = GlowMode.standard.rawValue
        case "Steady": saved = GlowMode.standard.rawValue
        default: break
        }
        mode = saved.flatMap(GlowMode.init(rawValue:)) ?? .standard
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        // Before the switch existed, any saved mode other than System meant Lidglow was in control.
        // A first launch leaves the logo to macOS.
        setEnabled(defaults.object(forKey: Self.enabledKey) as? Bool ?? (saved != nil))
    }

    func select(_ mode: GlowMode) {
        if mode != self.mode { stop() }
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        start()
    }

    /// Turning Lidglow off stops the glow loop and restores the logo to macOS.
    func setEnabled(_ on: Bool) {
        if !on { stop() }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        start()
    }

    private func start() {
        updateIcon()
        audioError = false
        phaseStart = ProcessInfo.processInfo.systemUptime
        hardwareCheck = 0
        guard enabled else {
            level = 0
            latestLevel = 0
            status = idleStatus
            return
        }
        if timer == nil { schedule(Self.fastTick) }
        tick()
    }

    /// The menu-bar icon shows an empty circle while Lidglow is holding the logo dark. Brightness drags
    /// call this on every change, so only touch the status item when the icon actually flips.
    private var iconLit: Bool?
    private func updateIcon() {
        let lit = !enabled || brightness > 0
        guard lit != iconLit else { return }
        iconLit = lit
        onIconChange?(lit)
    }

    // Music samples audio every tick, so it keeps the full rate while sound is playing. Even a 3 s
    // breath doesn't need 60 Hz, and a settled, paused, or silent glow only needs to notice drift, lid
    // closure, or a new target. During silence the audio callback wakes the loop on the first beat.
    private static let fastTick = 1 / 60.0
    private static let breatheTick = 1 / 30.0
    private static let idleTick = 0.25
    private static let silenceDelay = 2.0

    private func schedule(_ interval: Double) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = interval >= Self.idleTick ? 0.05 : 0
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleNextTick() {
        guard let timer else { return }
        let interval: Double
        if !(displaysAwake && sessionActive && mayRun) || (mode == .music && audioError) {
            interval = Self.idleTick
        } else {
            switch mode {
            case .music:
                let now = ProcessInfo.processInfo.systemUptime
                let silent = lastSignal.map { now - $0 >= Self.silenceDelay } ?? true
                if silent && (!hasHardware || logo.isSettled) {
                    music.armWake()
                    interval = Self.idleTick
                } else {
                    interval = Self.fastTick
                }
            case .breathe: interval = Self.breatheTick
            case .standard: interval = !hasHardware || logo.isSettled ? Self.idleTick : Self.fastTick
            }
        }
        if abs(timer.timeInterval - interval) > 1e-6 { schedule(interval) }
    }

    /// Something changed that the glow should react to right away instead of on the next idle tick.
    private func speedUp() {
        if let timer, timer.timeInterval > Self.fastTick + 1e-6 { schedule(Self.fastTick) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pause()
    }

    private func pause() {
        music.stop()
        logo.restore()
        lastSignal = nil
    }

    @objc private func screenSleep() { displaysAwake = false; pause() }
    @objc private func screenWake() { displaysAwake = true; hardwareCheck = 0; speedUp() }
    @objc private func lockSession() { sessionActive = false; pause() }
    @objc private func unlockSession() { sessionActive = true; hardwareCheck = 0; speedUp() }

    private func tick() {
        guard enabled else { return }
        defer { scheduleNextTick() }
        let now = ProcessInfo.processInfo.systemUptime
        if now >= hardwareCheck {
            mayRun = !hasHardware || (logo.awake && !logo.bridge.lidClosed)
            hardwareCheck = now + 0.35
        }
        guard displaysAwake && sessionActive && mayRun else {
            pause()
            publishLevel(0)
            publishStatus("Paused while the lid or screen is inactive")
            return
        }
        if mode == .music && !music.running && !audioError {
            do { try music.start() }
            catch {
                pause()
                audioError = true
                publishStatus(error.localizedDescription)
                publishLevel(0)
            }
        }
        if mode == .music && audioError { return }
        let target: Double
        let label: String
        switch mode {
        case .standard: target = brightness; label = brightness > 0 ? "Standard glow" : "Lid logo off"
        case .breathe:
            target = brightness * (0.15 + 0.85 * (1 - cos((now - phaseStart) * 2 * .pi / breatheSpeed.period)) / 2)
            label = "Breathing"
        case .music:
            let signal = music.level(at: now)
            if signal > SystemMusic.soundThreshold { lastSignal = now }
            let pulse = min(1, max(0, (signal - SystemMusic.soundThreshold) * sensitivity))
            let base = idleGlow ? min(idleBrightness, brightness * 0.90) : 0
            target = base + (brightness - base) * pulse
            label = lastSignal.map { now - $0 < Self.silenceDelay } == true
                ? "Reacting to system audio" : "Waiting for music · Play something on your Mac"
        }
        if hasHardware {
            guard logo.takeControl(),
                  logo.follow(target, now: now, rise: mode == .music ? 0.065 : 0.17,
                              fall: mode == .music ? 0.15 : 0.22,
                              tolerance: mode == .music && idleGlow && target == idleBrightness
                                ? min(0.012, target / 2) : 0.045) else {
                stop()
                publishLevel(0)
                publishStatus("Couldn’t control the lid logo. Select a mode to retry.")
                return
            }
        }
        publishLevel(mode == .music && hasHardware ? logo.measuredLevel : target)
        publishStatus(hasHardware ? label : "Preview · " + label)
    }

    private func publishLevel(_ value: Double) {
        latestLevel = value
        guard panelVisible else { return }
        let threshold = mode == .music ? 0.003 : 0.012
        if abs(value - level) > threshold || (value == 0 && level != 0) { level = value }
    }

    private func publishStatus(_ value: String) {
        if status != value { status = value }
    }

    func openAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
