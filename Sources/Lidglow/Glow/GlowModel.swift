// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import Combine
import os

final class GlowModel: ObservableObject {
    @Published private(set) var mode: GlowMode = .standard
    /// Whether Lidglow drives the logo. Off hands the logo back to macOS, which was System mode in build 1 (tagged v1.0).
    @Published private(set) var enabled = false
    @Published private(set) var level = 0.0
    @Published private(set) var status = "Checking lid hardware…"
    @Published private(set) var audioError = false
    /// Each mode keeps its own brightness, so turning Standard off doesn't leave Breathe or Music (or an
    /// automatic switch to Music) dark. Saved per mode.
    @Published private var brightnessByMode = Dictionary(uniqueKeysWithValues: GlowMode.allCases.map {
        ($0, GlowModel.savedBrightness(for: $0))
    })
    /// The selected mode's brightness, which the panel's Brightness slider shows and sets.
    var brightness: Double {
        get { brightness(for: mode) }
        set { setBrightness(newValue, for: mode) }
    }
    /// The selected mode's slider range. Only Standard can turn the logo off. Breathe and Music keep a
    /// 5% floor, so they always glow.
    var brightnessRange: ClosedRange<Double> { Self.minimumBrightness(for: mode)...1 }

    func brightness(for mode: GlowMode) -> Double { brightnessByMode[mode] ?? Self.defaultBrightness }

    private func setBrightness(_ value: Double, for mode: GlowMode) {
        var value = min(1, max(Self.minimumBrightness(for: mode), value))
        // The far left of Standard's slider turns the logo off, so snap a near-zero drag to exactly zero.
        if mode == .standard && value < 0.01 { value = 0 }
        brightnessByMode[mode] = value
        UserDefaults.standard.set(value, forKey: Self.brightnessKey(for: mode))
        updateIcon()
        speedUp()
    }

    private static let defaultBrightness = 0.82
    static func minimumBrightness(for mode: GlowMode) -> Double { mode == .standard ? 0 : 0.05 }
    private static func brightnessKey(for mode: GlowMode) -> String { "brightness.\(mode.rawValue)" }

    /// Before each mode had its own brightness, one shared value was saved as "brightness". Each mode
    /// starts from it, raised to the mode's floor. If it was off, Breathe and Music start at the default.
    private static func savedBrightness(for mode: GlowMode) -> Double {
        let defaults = UserDefaults.standard
        let floor = minimumBrightness(for: mode)
        if let saved = defaults.object(forKey: brightnessKey(for: mode)) as? Double {
            return min(1, max(floor, saved))
        }
        let shared = defaults.object(forKey: "brightness") as? Double ?? defaultBrightness
        if shared == 0 && floor > 0 { return defaultBrightness }
        return min(1, max(floor, shared))
    }
    @Published var sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }

    @Published var eqPreset = UserDefaults.standard.string(forKey: "eqPreset")
        .flatMap(EQPreset.init(saved:)) ?? .bass {
        didSet {
            UserDefaults.standard.set(eqPreset.rawValue, forKey: "eqPreset")
            music.preset = eqPreset
        }
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

    /// Where Music mode gets its sound. Chosen apps by default. The microphone is only ever opened when
    /// the user picks it here and macOS has granted access. Set it through `selectMusicSource(_:)`.
    @Published private(set) var musicSource = UserDefaults.standard.string(forKey: "musicSource")
        .flatMap(MusicSource.init(rawValue:)) ?? .chosenApps {
        didSet {
            UserDefaults.standard.set(musicSource.rawValue, forKey: "musicSource")
            applyMusicSource()
            updatePlaybackWatch()
        }
    }
    /// The user picked Microphone, but macOS doesn't allow Lidglow to use it.
    @Published private(set) var microphoneDenied = false
    static let defaultMusicApps = ["com.spotify.client", "com.apple.Music"]
    /// Bundle IDs of the apps Music listens to when the source is `.chosenApps`.
    @Published var musicApps = UserDefaults.standard.stringArray(forKey: "musicApps") ?? GlowModel.defaultMusicApps {
        didSet {
            UserDefaults.standard.set(musicApps, forKey: "musicApps")
            applyMusicSource()
            updatePlaybackWatch()
        }
    }

    private var musicInput: SystemMusic.Source {
        switch musicSource {
        case .chosenApps: return .apps(Set(musicApps))
        case .allApps: return .allApps
        case .microphone: return .microphone
        }
    }

    private func applyMusicSource() {
        music.source = musicInput
        // Clear an error from the previous source, such as revoked microphone access, so the next tick
        // starts the new one.
        if audioError && mode == .music { audioError = false; music.stop() }
        speedUp()
    }

    /// Switches Music's source. Choosing the microphone asks macOS for access the first time, and only
    /// switches once it's granted.
    func selectMusicSource(_ source: MusicSource) {
        microphoneDenied = false
        guard source == .microphone else { musicSource = source; return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            musicSource = .microphone
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.musicSource = .microphone } else { self.microphoneDenied = true }
                }
            }
        default:
            microphoneDenied = true
        }
    }

    /// Settings → Music → Automatically switch to Music. Off by default. With Chosen apps, those apps
    /// trigger it. With All apps, any app except alert sounds does. The microphone isn't playback.
    @Published var autoMusic = UserDefaults.standard.bool(forKey: "autoMusic") {
        didSet {
            UserDefaults.standard.set(autoMusic, forKey: "autoMusic")
            updatePlaybackWatch()
        }
    }

    /// Settings → Music → Switch back after silence. It's the only way out of Music other than picking a
    /// mode, including after an automatic switch. Music returns to the mode used before it once it has
    /// heard nothing above `SystemMusic.soundThreshold` for this long. Ten seconds by default.
    @Published var musicTimeout = (UserDefaults.standard.object(forKey: "musicTimeout") as? Int)
        .flatMap(MusicTimeout.init(rawValue:)) ?? .tenSeconds {
        didSet {
            UserDefaults.standard.set(musicTimeout.rawValue, forKey: "musicTimeout")
            // Count the new limit from now, not from the last sound.
            musicHeard = nil
            updatePlaybackWatch()
        }
    }

    /// Settings → Agents → Pulse when an agent needs you. Off by default. While it's off, every agent link
    /// is ignored.
    @Published var agentAlerts = UserDefaults.standard.bool(forKey: "agentAlerts") {
        didSet {
            UserDefaults.standard.set(agentAlerts, forKey: "agentAlerts")
            if !agentAlerts { clearAgents() }
        }
    }
    /// The agents whose links Lidglow acts on. All of them by default, once Agent alerts is on.
    @Published var alertingAgents = Set((UserDefaults.standard.stringArray(forKey: "agentAlertAgents")
        ?? CodingAgent.allCases.map(\.rawValue)).compactMap(CodingAgent.init(rawValue:))) {
        didSet {
            UserDefaults.standard.set(CodingAgent.allCases.filter(alertingAgents.contains).map(\.rawValue),
                                      forKey: "agentAlertAgents")
            for agent in waitingAgents.keys where !alertingAgents.contains(agent) { clear(agent) }
        }
    }
    /// Also pulse when an agent finishes a turn, not only when it's waiting on a prompt. On by default.
    @Published var agentAlertsOnFinish = UserDefaults.standard.object(forKey: "agentAlertsOnFinish") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(agentAlertsOnFinish, forKey: "agentAlertsOnFinish")
            if !agentAlertsOnFinish {
                for (agent, waiting) in waitingAgents where waiting.signal == .done { clear(agent) }
            }
        }
    }
    /// Settings → Agents → Pulse even when Lidglow is off. Off by default. When on, a pulse takes the logo
    /// from macOS while the panel's switch is off, and hands it straight back when the pulse ends, with
    /// the glow loop stopped in between.
    @Published var agentAlertsWhileOff = UserDefaults.standard.bool(forKey: "agentAlertsWhileOff") {
        didSet {
            UserDefaults.standard.set(agentAlertsWhileOff, forKey: "agentAlertsWhileOff")
            if !agentAlertsWhileOff && !enabled { clearAgents() }
        }
    }
    /// How long a pulse lasts if neither the agent nor opening the panel clears it. Fifteen minutes by default.
    @Published var agentAlertTimeout = (UserDefaults.standard.object(forKey: "agentAlertTimeout") as? Int)
        .flatMap(AgentAlertTimeout.init(rawValue:)) ?? .fifteenMinutes {
        didSet { UserDefaults.standard.set(agentAlertTimeout.rawValue, forKey: "agentAlertTimeout") }
    }
    /// The pulse's own peak, separate from the modes' brightness, so an alert shows even while Standard
    /// holds the logo off. Full by default.
    @Published var agentAlertBrightness = min(1, max(0.05, UserDefaults.standard.object(forKey: "agentAlertBrightness")
        as? Double ?? 1)) {
        didSet { UserDefaults.standard.set(agentAlertBrightness, forKey: "agentAlertBrightness") }
    }
    /// Settings → Agents → Stop pulsing when I click in the agent's app. On by default. Clicks are watched
    /// only while an agent that named its app is waiting.
    @Published var agentAlertsClearOnClick = UserDefaults.standard.object(forKey: "agentAlertsClearOnClick") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(agentAlertsClearOnClick, forKey: "agentAlertsClearOnClick")
            updateClickWatch()
        }
    }
    private struct WaitingAgent {
        var signal: AgentSignal
        /// The bundle ID of the app the agent runs in, if its hook named one.
        var app: String?
        /// When its latest signal arrived, in system uptime.
        var since: Double
    }
    /// The agents waiting on the user, and why. The logo pulses while this isn't empty, whatever the mode,
    /// then goes back to the mode. Not saved: a relaunch starts with nothing waiting.
    private var waitingAgents: [CodingAgent: WaitingAgent] = [:]
    private let clickWatcher = AgentClickWatcher()
    /// A click this soon after an agent's signal doesn't clear it, so a click already under way when the
    /// agent finished doesn't cancel the pulse before it's seen.
    private static let clickGrace = 1.0
    /// When the current pulse started, which sets its rhythm, and when the latest signal arrived, which
    /// the timeout counts from. Both use system uptime, like the glow loop.
    private var pulseStart: Double?
    private var lastAgentSignal = 0.0
    private var pulseReducesMotion = false

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
    private let otherApps = OtherLogoApps()
    private let playback = PlaybackWatcher()
    private var timer: Timer?
    private var phaseStart = 0.0
    private var sessionActive = true
    private var displaysAwake = true
    private var hardwareCheck = 0.0
    private var mayRun = true
    private var lastSignal: Double?
    /// When Music last heard sound, for the silence timeout. Cleared whenever the glow pauses, so time
    /// locked, asleep, or with the lid closed doesn't count as silence.
    private var musicHeard: Double?
    private var latestLevel = 0.0
    /// The preview only needs live levels while the panel is on screen. A hidden SwiftUI host
    /// still lays out on every change, which costs more than the glow loop itself in Music mode.
    @Published var panelVisible = false {
        didSet {
            guard panelVisible && !oldValue else { return }
            // Opening the panel acknowledges every waiting agent.
            clearAgents()
            publishLevel(latestLevel)
        }
    }
    var onIconChange: ((Bool) -> Void)?
    var onRiseFromDark: (() -> Void)? {
        didSet { logo.onRiseFromDark = onRiseFromDark }
    }

    init() {
        logo.recoverAfterUnexpectedExit()
        status = idleStatus
        Logger.hardware.notice("Hardware check: \(self.idleStatus, privacy: .public)")
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
        music.source = musicInput
        music.onFailure = { [weak self] error in
            guard let self, self.mode == .music else { return }
            self.pause()
            self.audioError = true
            self.publishStatus(error.localizedDescription)
            self.publishLevel(0)
        }
        music.preset = eqPreset
        otherApps.onChange = { [weak self] in self?.otherAppsChanged() }
        playback.onChange = { [weak self] playing in self?.playbackChanged(playing) }
        clickWatcher.onClick = { [weak self] app in self?.clicked(in: app) }
    }

    /// The logo can be controlled: the hardware is there and the private CoreBrightness interface looks
    /// as expected. Otherwise everything runs as a preview and nothing is sent to the logo.
    var hasHardware: Bool { logo.bridge.hardwarePresent && logo.bridge.serviceAvailable }
    private var idleStatus: String {
        if !logo.bridge.hardwarePresent { return "Preview only · No controllable lid logo found" }
        if !logo.bridge.serviceAvailable { return "Preview only · Lid logo service unavailable" }
        return logo.available ? "macOS is managing the lid logo" : "Lid logo service unavailable"
    }

    private static let modeKey = "glowMode"
    /// The mode selected before Music, which the silence timeout returns to. Saved so it survives a relaunch.
    private static let modeBeforeMusicKey = "modeBeforeMusic"
    private static let enabledKey = "glowEnabled"

    func restoreSelectedMode() {
        let defaults = UserDefaults.standard
        var saved = defaults.string(forKey: Self.modeKey)
        // Build 1 (tagged v1.0) saved System, Off, and Steady as modes. System is now the switch turned off,
        // and Off and Steady are both Standard, with Off at zero brightness.
        switch saved {
        case "System": defaults.set(false, forKey: Self.enabledKey); saved = nil
        case "Off": setBrightness(0, for: .standard); saved = GlowMode.standard.rawValue
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
        if mode == .music && self.mode != .music {
            UserDefaults.standard.set(self.mode.rawValue, forKey: Self.modeBeforeMusicKey)
        }
        if mode != self.mode { stop() }
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        start()
    }

    /// Turning Lidglow off stops the glow loop and restores the logo to macOS.
    func setEnabled(_ on: Bool) {
        if !on { stop(); clearAgents() }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        start()
        updatePlaybackWatch()
    }

    /// Seconds of silence before Music switches back, or nil when it doesn't count silence. Automatically
    /// follows apps' audio streams, so with Microphone it falls back to ten seconds of silence.
    private var silenceLimit: Double? {
        if musicTimeout == .automatic { return musicSource == .microphone ? 10 : nil }
        return musicTimeout.seconds
    }

    /// Watches apps only while switching into or out of Music can act on them: the chosen apps, or every
    /// app with All apps.
    private func updatePlaybackWatch() {
        playback.bundleIDs = musicSource == .allApps ? nil : Set(musicApps)
        if (autoMusic || musicTimeout == .automatic) && enabled && musicSource != .microphone {
            playback.start()
        } else {
            playback.stop()
        }
    }

    /// A chosen app started playing, or every chosen app stopped. Switching in happens only when playback
    /// starts, so a mode picked by hand while music plays stays until playback stops and starts again.
    /// Switching out on stop happens only with Switch back after silence set to Automatically.
    private func playbackChanged(_ playing: Bool) {
        guard enabled else { return }
        if playing {
            guard autoMusic, mode != .music else { return }
            Logger.audio.notice("Switching to Music automatically")
            select(.music)
        } else if musicTimeout == .automatic && mode == .music {
            Logger.audio.notice("Leaving Music because playback stopped")
            leaveMusic()
        }
    }

    /// A signal from an agent's hook, through a `lidglow://agent/…` link. It's acted on only while Agent
    /// alerts and that agent are turned on, and while Lidglow controls the logo or Pulse even when Lidglow
    /// is off is on. The pulse goes through the glow loop and `LidLogo` like any mode, so lock, sleep, lid
    /// close, the switch, and quit still hand the logo back to macOS mid-pulse.
    func receive(_ request: AgentRequest) {
        guard agentAlerts, alertingAgents.contains(request.agent) else { return }
        switch request.signal {
        case .clear:
            clear(request.agent)
        case .attention, .done:
            // With the switch off the logo belongs to macOS unless the user allowed pulses then. With the
            // panel open, the user is already looking at Lidglow.
            guard enabled || agentAlertsWhileOff, !panelVisible else { return }
            if request.signal == .done && !agentAlertsOnFinish { return }
            Logger.agents.notice("\(request.agent.title, privacy: .public) asked for attention (\(request.signal.rawValue, privacy: .public))")
            let now = ProcessInfo.processInfo.systemUptime
            if waitingAgents.isEmpty {
                pulseStart = now
                pulseReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
            // A finished turn doesn't replace a pending prompt from the same agent.
            let previous = waitingAgents[request.agent]
            waitingAgents[request.agent] = WaitingAgent(
                signal: previous?.signal == .attention ? .attention : request.signal,
                app: request.app ?? previous?.app, since: now)
            updateClickWatch()
            lastAgentSignal = now
            // With the switch off there's no glow loop, so start one just for the pulse. With it on, a
            // stopped loop is waiting for the user to retry (or for another logo app to quit), so leave it.
            if enabled { speedUp() } else if timer == nil { start() }
        }
    }

    private func clear(_ agent: CodingAgent) {
        guard waitingAgents.removeValue(forKey: agent) != nil else { return }
        Logger.agents.notice("\(agent.title, privacy: .public) no longer needs attention")
        updateClickWatch()
        if waitingAgents.isEmpty { pulseEnded() }
    }

    private func clearAgents() {
        guard !waitingAgents.isEmpty else { return }
        waitingAgents = [:]
        updateClickWatch()
        pulseEnded()
    }

    /// Watches clicks only while it's turned on and a waiting agent named its app.
    private func updateClickWatch() {
        if agentAlertsClearOnClick && waitingAgents.values.contains(where: { $0.app != nil }) {
            clickWatcher.start()
        } else {
            clickWatcher.stop()
        }
    }

    /// A click landed in a window of `app`. Every agent waiting in that app is cleared, as if it had
    /// reported working again, unless its signal arrived within the last second.
    private func clicked(in app: String) {
        let now = ProcessInfo.processInfo.systemUptime
        for (agent, waiting) in waitingAgents where waiting.app == app && now - waiting.since >= Self.clickGrace {
            Logger.agents.notice("Clicked in \(agent.title, privacy: .public)'s app")
            clear(agent)
        }
    }

    /// Hands the logo back to the mode, or to macOS if the switch is off, which also stops the glow loop.
    /// Music starts its silence clock again rather than counting the pulse as silence.
    private func pulseEnded() {
        pulseStart = nil
        musicHeard = nil
        lastSignal = nil
        if enabled {
            speedUp()
        } else {
            stop()
            start()
        }
    }

    /// The glow loop runs while the switch is on, and while the switch is off only for an agent's pulse.
    private var shouldRun: Bool { enabled || pulseStart != nil }

    private var agentStatus: String {
        guard waitingAgents.count == 1, let (agent, waiting) = waitingAgents.first else {
            return "\(waitingAgents.count) agents are waiting for you"
        }
        return waiting.signal == .attention ? "\(agent.title) needs your input" : "\(agent.title) finished"
    }

    private func start() {
        updateIcon()
        audioError = false
        phaseStart = ProcessInfo.processInfo.systemUptime
        hardwareCheck = 0
        guard shouldRun else {
            level = 0
            latestLevel = 0
            status = idleStatus
            return
        }
        // Another logo utility is running. Leave the logo alone until it quits, which `otherAppsChanged`
        // hears about, so no timer is needed in the meantime.
        if hasHardware, let other = otherApps.running {
            level = 0
            latestLevel = 0
            status = "\(other) is controlling the lid logo. Quit it to use Lidglow."
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
        if !(displaysAwake && sessionActive && mayRun) {
            interval = Self.idleTick
        } else if pulseStart != nil {
            interval = Self.breatheTick
        } else if mode == .music && audioError {
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

    private func otherAppsChanged() {
        guard shouldRun, hasHardware else { return }
        // `stop()` hands the logo back to macOS through the normal restore path before anything else
        // touches it.
        stop()
        start()
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
        musicHeard = nil
    }

    /// The silence timeout ran out: go back to the mode selected before Music, as if picked by hand.
    private func leaveMusic() {
        guard mode == .music else { return }
        let previous = UserDefaults.standard.string(forKey: Self.modeBeforeMusicKey)
            .flatMap(GlowMode.init(rawValue:)).flatMap { $0 == .music ? nil : $0 } ?? .standard
        select(previous)
    }

    @objc private func screenSleep() { displaysAwake = false; pause() }
    @objc private func screenWake() { displaysAwake = true; hardwareCheck = 0; speedUp() }
    @objc private func lockSession() { sessionActive = false; pause() }
    @objc private func unlockSession() { sessionActive = true; hardwareCheck = 0; speedUp() }

    private func tick() {
        guard shouldRun else { return }
        defer { scheduleNextTick() }
        let now = ProcessInfo.processInfo.systemUptime
        if now >= hardwareCheck {
            mayRun = !hasHardware || (logo.awake && !logo.bridge.lidClosed)
            hardwareCheck = now + 0.35
        }
        // Checked before the pause below, so a pulse left behind a lock still times out.
        if pulseStart != nil, let limit = agentAlertTimeout.seconds, now - lastAgentSignal >= limit {
            Logger.agents.notice("Agent alert timed out after \(Int(limit)) s")
            clearAgents()
            // With the switch off, that stopped the loop and handed the logo back to macOS.
            guard shouldRun else { return }
        }
        guard displaysAwake && sessionActive && mayRun else {
            pause()
            publishLevel(0)
            publishStatus("Paused while the lid or screen is inactive")
            return
        }
        // An agent is waiting: the pulse takes over from the mode until it's cleared. Music's input keeps
        // running if it already was, so the music picks up again right away.
        if let pulseStart {
            let lit = AgentPulse.isLit(elapsed: now - pulseStart, reduceMotion: pulseReducesMotion)
            let target = lit ? agentAlertBrightness : 0
            if hasHardware {
                let fades = AgentPulse.fades(reduceMotion: pulseReducesMotion)
                guard driveLogo({ logo.follow(target, now: now, rise: fades.rise, fall: fades.fall) }) else { return }
            }
            publishLevel(hasHardware ? logo.measuredLevel : target)
            publishStatus(hasHardware ? agentStatus : "Preview · " + agentStatus)
            return
        }
        if mode == .music && !music.started && !audioError {
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
            if let limit = silenceLimit {
                if signal > SystemMusic.soundThreshold || musicHeard == nil {
                    musicHeard = now
                } else if let heard = musicHeard, now - heard >= limit {
                    // Switch modes after this tick finishes, rather than restarting the loop inside it.
                    Logger.audio.notice("Leaving Music after \(Int(limit)) s of silence")
                    DispatchQueue.main.async { [weak self] in self?.leaveMusic() }
                }
            }
            let pulse = min(1, max(0, (signal - SystemMusic.soundThreshold) * sensitivity))
            let base = idleGlow ? min(idleBrightness, brightness * 0.90) : 0
            target = base + (brightness - base) * pulse
            if lastSignal.map({ now - $0 < Self.silenceDelay }) == true {
                switch musicSource {
                case .chosenApps: label = "Reacting to your music apps"
                case .allApps: label = "Reacting to system audio"
                case .microphone: label = "Reacting to the microphone"
                }
            } else if music.waitingForApps {
                label = musicApps.isEmpty ? "No music apps chosen · Choose them in Settings"
                                          : "Waiting for music · Open a music app chosen in Settings"
            } else if musicSource == .microphone {
                label = "Waiting for sound · Listening to the microphone"
            } else {
                label = "Waiting for music · Play something on your Mac"
            }
        }
        if hasHardware {
            let driven: Bool
            if mode == .breathe {
                driven = driveLogo { followBreath(now: now) }
            } else {
                driven = driveLogo {
                    logo.follow(target, now: now, rise: mode == .music ? 0.065 : 0.17,
                                fall: mode == .music ? 0.15 : 0.22,
                                tolerance: mode == .music && idleGlow && target == idleBrightness
                                    ? min(0.012, target / 2) : 0.045)
                }
            }
            guard driven else { return }
        }
        publishLevel(mode == .music && hasHardware ? logo.measuredLevel : target)
        publishStatus(hasHardware ? label : "Preview · " + label)
    }

    /// Takes control of the logo and moves it with `follow`. If that fails, or another app is changing the
    /// logo, it stops the glow loop, which hands the logo back to macOS, and returns false.
    private func driveLogo(_ follow: () -> Bool) -> Bool {
        guard logo.takeControl() && follow() else {
            stop()
            publishLevel(0)
            publishStatus("Couldn’t control the lid logo. Select a mode to retry.")
            return false
        }
        if logo.interferenceDetected {
            stop()
            publishLevel(0)
            publishStatus("Another app is changing the lid logo. Quit it, then select a mode to retry.")
            return false
        }
        return true
    }

    /// Chasing the moving breath target made the logo fade a little, hold, and fade again, because
    /// each time it caught up it stopped until the target moved past the tolerance. That stepping was
    /// worst at Slow. Instead, aim each ramp at the breath's next peak or trough and time it to arrive
    /// there, so the hardware's own smooth fade carries a whole half-breath.
    private func followBreath(now: Double) -> Bool {
        let period = breatheSpeed.period
        let phase = ((now - phaseStart) / period).truncatingRemainder(dividingBy: 1)
        let rising = phase < 0.5
        let extreme = rising ? brightness : brightness * 0.15
        let remaining = max(0.05, ((rising ? 0.5 : 1) - phase) * period)
        return logo.follow(extreme, now: now, rise: remaining, fall: remaining, tolerance: 0.03,
                           maxDuration: period)
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

    /// Opens the privacy pane for the current source: Microphone, or Screen & System Audio Recording.
    func openAudioSettings() {
        let pane = musicSource == .microphone ? "Privacy_Microphone" : "Privacy_AudioCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
