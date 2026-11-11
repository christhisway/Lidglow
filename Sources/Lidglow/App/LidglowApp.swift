import AppKit
import SwiftUI

/// Lays its subviews out from the top, so the panel's backdrop and content stay pinned under the menu
/// bar while only their bottom edge moves.
private final class TopAnchoredView: NSView {
    override var isFlipped: Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

final class LidglowApp: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private let model = GlowModel()
    private var panel: MenuPanel?
    private var host: NSHostingController<GlowPanel>?
    /// The glass panel itself. The window is transparent, and only this view animates when the panel's
    /// height changes, because animating the window frame let the top of the panel visibly slide.
    private var backdrop: NSView?
    private var resizeGeneration = 0
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var settingsWindow: SettingsWindow?
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lidglow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignals()
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item = status
        status.button?.target = self
        status.button?.action = #selector(statusItemClicked)
        // Act on mouse-up for both buttons so a right-click or Control-click can open the context menu.
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.onIconChange = { [weak self] in self?.setIcon(lit: $0) }
        model.onRiseFromDark = { [weak self] in
            guard let button = self?.item?.button else { return }
            button.alphaValue = button.alphaValue == 1 ? 0.98 : 1
        }
        setIcon(lit: true)
        model.restoreSelectedMode()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }

    private func setIcon(lit: Bool) {
        item?.button?.image = NSImage(systemSymbolName: lit ? "waveform.circle" : "circle",
                                      accessibilityDescription: "Lidglow")
        item?.button?.toolTip = "Lidglow"
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return togglePanel() }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        closePanel()
        // Attaching the menu only for this click lets the status item show it with the system's own
        // highlight and placement, while a normal click still toggles the panel.
        item?.menu = contextMenu
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    @objc private func openSettings() {
        closePanel()
        if settingsWindow == nil {
            settingsWindow = SettingsWindow { [weak self] in self?.settingsWindow = nil }
        }
        // Lidglow is a menu-bar app, so it has to activate itself or the window opens behind other apps.
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
            return
        }
        if panel == nil {
            let host = NSHostingController(rootView: GlowPanel(model: model, openSettings: { [weak self] in
                self?.openSettings()
            }, onHeightChange: { [weak self] height in
                // SwiftUI reports the new height in the same pass that adds or removes controls, so the
                // window grows or shrinks with them rather than a run-loop pass later.
                guard let self, self.panel?.isVisible == true else { return }
                self.positionPanel(contentHeight: height, animate: true)
            }))
            host.sizingOptions = []
            // No scroll view: the panel always fits its content, and scrolling only ever revealed empty
            // space. Both containers are flipped, so the content stays pinned to the top. None of them
            // draws a focus ring, which outlined the whole panel when it opened.
            host.view.focusRingType = .none
            let document = TopAnchoredView()
            document.addSubview(host.view)
            let backdrop = MenuPanel.backdrop(containing: document)
            backdrop.focusRingType = .none
            let root = TopAnchoredView()
            root.addSubview(backdrop)
            let container = NSViewController()
            container.view = root
            container.addChild(host)
            self.backdrop = backdrop

            let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
            panel.title = "Lidglow Controls"
            panel.contentViewController = container
            panel.level = .popUpMenu
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            self.panel = panel
            self.host = host
        }
        model.panelVisible = true
        guard positionPanel(), let panel else { model.panelVisible = false; return }
        panel.makeKeyAndOrderFront(nil)
        // Start with nothing focused, so no focus ring appears until the user presses Tab.
        panel.makeFirstResponder(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.closePanel(); return nil }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers == .command && event.charactersIgnoringModifiers == "," {
                    self.openSettings()
                    return nil
                }
            } else if event.window !== self.panel && !self.clickIsOnStatusItem() {
                self.closePanel()
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            guard let self, !self.clickIsOnStatusItem() else { return }
            self.closePanel()
        }
    }

    /// Clicks on the menu-bar icon belong to `statusItemClicked()`. If a monitor closed the panel on mouse-down,
    /// the button's action would find it hidden and open it again, so the icon could never close it.
    /// Test the click's screen position rather than its window, since the status item's window isn't
    /// guaranteed to be the one the event reports.
    private func clickIsOnStatusItem() -> Bool {
        guard let button = item?.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    /// Places the panel under the menu-bar icon, clamped to the visible screen, and sizes it to its
    /// content. Pass `contentHeight` when SwiftUI has already measured it. With `animate`, only the glass
    /// backdrop animates, over the same duration as the panel's SwiftUI animation. When growing, the
    /// transparent window takes its final size first; when shrinking, it follows once the backdrop has.
    @discardableResult
    private func positionPanel(contentHeight: CGFloat? = nil, animate: Bool = false) -> Bool {
        guard let panel, let host, let backdrop, let button = item?.button,
              let menuWindow = button.window, let screen = menuWindow.screen else { return false }
        let anchor = menuWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let top = min(visible.maxY, anchor.minY - 6)
        guard top > visible.minY, visible.width > 0 else { return false }
        let width = min(350, visible.width)
        // The content is pinned to the top of a flexible frame, so propose no height to get its natural one.
        let natural = ceil(contentHeight ?? host.sizeThatFits(in: NSSize(width: width, height: 0)).height)
        guard natural > 0 else { return false }
        let height = min(natural, top - visible.minY)
        let x = min(max(anchor.midX - width / 2, visible.minX), visible.maxX - width)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        let panelBounds = NSRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = NSRect(x: 0, y: 0, width: width, height: natural)
        resizeGeneration += 1
        guard animate, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              backdrop.frame.height != height, backdrop.frame.width == width else {
            panel.setFrame(frame, display: true)
            backdrop.frame = panelBounds
            panel.invalidateShadow()
            return true
        }
        let generation = resizeGeneration
        let growing = height > backdrop.frame.height
        if growing { panel.setFrame(frame, display: false) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = GlowPanel.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdrop.animator().frame = panelBounds
        } completionHandler: { [weak self] in
            guard let self, generation == self.resizeGeneration else { return }
            if !growing { panel.setFrame(frame, display: true) }
            panel.invalidateShadow()
        }
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

    /// `kill`, `pkill`, Ctrl-C in Terminal, and a closed Terminal window end the app without a normal
    /// quit, which would leave the logo where Lidglow last put it. Route them through a normal quit so
    /// the logo goes back to macOS. `kill -9` and crashes can't be caught. The next launch repairs those.
    private func handleTerminationSignals() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}
