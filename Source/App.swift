import AppKit
import Combine
import SwiftUI

enum GlowMode: String, CaseIterable {
    case system = "System"
    case off = "Off"
    case steady = "Steady"
    case breathe = "Breathe"
    case music = "Music"

    var icon: String {
        switch self {
        case .system: "sparkle"
        case .off: "circle"
        case .steady: "sun.max"
        case .breathe: "wind"
        case .music: "waveform"
        }
    }
}

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
    var panelVisible = false {
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
    }

    var hasHardware: Bool { logo.bridge.hardwarePresent }
    private var idleStatus: String {
        if !hasHardware { return "Preview only · No controllable lid logo found" }
        return logo.available ? "macOS is managing the lid logo" : "Lid logo service unavailable"
    }

    func select(_ mode: GlowMode) {
        if mode != self.mode { stop() }
        self.mode = mode
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

    // Music samples audio every tick, so it keeps the full rate. A 5 s breath doesn't need 60 Hz,
    // and a settled or paused glow only needs to notice drift, lid closure, or a new target.
    private static let fastTick = 1 / 60.0
    private static let breatheTick = 1 / 30.0
    private static let idleTick = 0.25

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
            case .music: interval = Self.fastTick
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
            if signal > 0.035 { lastSignal = now }
            let pulse = min(1, max(0, (signal - 0.035) * sensitivity))
            let base = idleGlow ? idleBrightness : 0
            target = base + (brightness - base) * pulse
            label = lastSignal.map { now - $0 < 2 } == true
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
        publishLevel(target)
        publishStatus(hasHardware ? label : "Preview · " + label)
    }

    private func publishLevel(_ value: Double) {
        latestLevel = value
        guard panelVisible else { return }
        if abs(value - level) > 0.012 || (value == 0 && level != 0) { level = value }
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

struct GlowPanel: View {
    @ObservedObject var model: GlowModel
    private let accent = Color(red: 0.48, green: 0.91, blue: 0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2).foregroundStyle(accent)
                Text("Lidglow").font(.headline)
                Spacer()
                Text("LID LIGHT").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
            }
            preview
            HStack(spacing: 4) {
                ForEach(GlowMode.allCases, id: \.self) { mode in
                    Button { model.select(mode) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: mode.icon).font(.system(size: 14, weight: .medium))
                            Text(mode.rawValue).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(model.mode == mode ? accent : .secondary)
                        .background(model.mode == mode ? accent.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
            }
            .padding(4)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            if model.mode == .music || model.mode == .steady || model.mode == .breathe {
                control("Brightness", value: $model.brightness, range: 0.05...1,
                        reading: "\(Int((model.brightness * 100).rounded()))%")
            }
            if model.mode == .music {
                control("Sensitivity", value: $model.sensitivity, range: 0.4...2.0,
                        reading: String(format: "%.1f×", model.sensitivity))
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Idle glow", isOn: $model.idleGlow).toggleStyle(.switch).controlSize(.small)
                    if model.idleGlow {
                        control("Idle brightness", value: $model.idleBrightness, range: model.idleBrightnessRange,
                                reading: "\(Int((model.idleBrightness * 100).rounded()))%")
                        Text("Amber preview · The lid LED glows white")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Text(model.status)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(model.status)
                Spacer(minLength: 12)
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
            if model.mode == .music {
                Button("System Audio Settings…") { model.openAudioSettings() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .preferredColorScheme(.dark)
    }

    private var preview: some View {
        let glow = model.mode == .system ? 0.65 : model.level
        let amber = Color(red: 1, green: 0.65, blue: 0.24)
        let previewColor = model.mode == .music && model.idleGlow ? amber : .white
        let haloColor = model.mode == .music && model.idleGlow ? amber : accent
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.055, green: 0.07, blue: 0.09))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.075))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.105)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)) }
                .frame(width: 152, height: 90)
            Image(systemName: "apple.logo")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(previewColor.opacity(0.14 + glow * 0.86))
                .shadow(color: haloColor.opacity(glow * 0.82), radius: 8)
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                         reading: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(reading).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).tint(accent).accessibilityLabel(title)
        }
    }
}

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class LidglowApp: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private let model = GlowModel()
    private var panel: MenuPanel?
    private var host: NSHostingController<GlowPanel>?
    private var layoutChanges: AnyCancellable?
    private var localMonitor: Any?
    private var outsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item = status
        status.button?.target = self
        status.button?.action = #selector(togglePanel)
        model.onIconChange = { [weak self] in self?.setIcon(lit: $0) }
        model.onRiseFromDark = { [weak self] in
            guard let button = self?.item?.button else { return }
            button.alphaValue = button.alphaValue == 1 ? 0.98 : 1
        }
        setIcon(lit: true)
        layoutChanges = Publishers.CombineLatest3(model.$mode, model.$idleGlow, model.$status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.panel?.isVisible == true else { return }
                self.positionPanel()
            }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }

    private func setIcon(lit: Bool) {
        item?.button?.image = NSImage(systemSymbolName: lit ? "waveform.circle" : "circle",
                                      accessibilityDescription: "Lidglow")
        item?.button?.toolTip = "Lidglow"
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
            return
        }
        if panel == nil {
            let host = NSHostingController(rootView: GlowPanel(model: model))
            host.sizingOptions = []
            let scroll = NSScrollView()
            scroll.drawsBackground = true
            scroll.backgroundColor = .windowBackgroundColor
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.documentView = host.view
            let container = NSViewController()
            container.view = scroll
            container.addChild(host)

            let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
            panel.title = "Lidglow Controls"
            panel.contentViewController = container
            panel.level = .popUpMenu
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.cornerRadius = 12
            panel.contentView?.layer?.masksToBounds = true
            panel.isOpaque = false
            panel.hasShadow = true
            self.panel = panel
            self.host = host
        }
        model.panelVisible = true
        guard positionPanel(), let panel else { model.panelVisible = false; return }
        if let scroll = panel.contentView as? NSScrollView, let document = scroll.documentView {
            let top = document.isFlipped ? 0 : max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        panel.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { self?.closePanel(); return nil }
            } else if event.window !== self?.panel && event.window !== self?.item?.button?.window {
                self?.closePanel()
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.closePanel()
        }
    }

    @discardableResult
    private func positionPanel() -> Bool {
        guard let panel, let host, let button = item?.button,
              let menuWindow = button.window, let screen = menuWindow.screen else { return false }
        let anchor = menuWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let top = min(visible.maxY, anchor.minY - 6)
        guard top > visible.minY, visible.width > 0 else { return false }
        let width = min(350, visible.width)
        let size = host.sizeThatFits(in: NSSize(width: width, height: 10_000))
        let height = min(ceil(size.height), top - visible.minY)
        let x = min(max(anchor.midX - width / 2, visible.minX), visible.maxX - width)
        host.view.setFrameSize(NSSize(width: width, height: ceil(size.height)))
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
        return true
    }

    private func closePanel() {
        panel?.orderOut(nil)
        model.panelVisible = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if panel?.isVisible == true && !positionPanel() { closePanel() }
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = LidglowApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
