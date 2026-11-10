import AppKit
import Combine

final class GlowModel: ObservableObject {
    @Published private(set) var mode: GlowMode = .system
    @Published private(set) var level = 0.0
    @Published private(set) var status = "Checking lid hardware…"
    @Published private(set) var audioError = false
    @Published var brightness = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 0.82 {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness"); speedUp() }
    }
    @Published var sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }

    @Published var idleGlow = UserDefaults.standard.bool(forKey: "idleGlow") {
        didSet { UserDefaults.standard.set(idleGlow, forKey: "idleGlow") }
    }
    @Published private var preferredIdleBrightness = UserDefaults.standard.object(forKey: "idleBrightness") as? Double {
        didSet { UserDefaults.standard.set(preferredIdleBrightness, forKey: "idleBrightness") }
    }

    var idleBrightnessRange: ClosedRange<Double> { 0.01...(brightness * 0.90) }
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

    func restoreSelectedMode() {
        if let saved = UserDefaults.standard.string(forKey: "glowMode"), let mode = GlowMode(rawValue: saved) {
            select(mode)
        }
    }

    func select(_ mode: GlowMode) {
        if mode != self.mode { stop() }
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "glowMode")
        onIconChange?(mode != .off)
        audioError = false
        phaseStart = ProcessInfo.processInfo.systemUptime
        hardwareCheck = 0
        if mode == .system {
            level = 0
            latestLevel = 0
            status = idleStatus
            return
        }
        if timer == nil { schedule(Self.fastTick) }
        tick()
    }

    // Music samples audio every tick, so it keeps the full rate while sound is playing. A 5 s breath
    // doesn't need 60 Hz, and a settled, paused, or silent glow only needs to notice drift, lid
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
            default: interval = !hasHardware || logo.isSettled ? Self.idleTick : Self.fastTick
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
        case .system: return
        case .off: target = 0; label = "Lid logo off"
        case .steady: target = brightness; label = "Steady glow"
        case .breathe:
            target = brightness * (0.15 + 0.85 * (1 - cos((now - phaseStart) * 2 * .pi / 5)) / 2)
            label = "Breathing"
        case .music:
            let signal = music.level(at: now)
            if signal > SystemMusic.soundThreshold { lastSignal = now }
            let pulse = min(1, max(0, (signal - SystemMusic.soundThreshold) * sensitivity))
            let base = idleGlow ? idleBrightness : 0
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
