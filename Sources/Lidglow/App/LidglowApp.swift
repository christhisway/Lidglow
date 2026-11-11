import AppKit
import SwiftUI

/// Holds the panel's SwiftUI content at the top, so the content stays put while the window's height
/// changes from the bottom edge.
private final class TopAnchoredView: NSView {
    override var isFlipped: Bool { true }
}

final class LidglowApp: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private let model = GlowModel()
    private var panel: MenuPanel?
    private var host: NSHostingController<GlowPanel>?
    /// The latest panel height reported while a Reduce Motion resize waits for SwiftUI's update to finish.
    private var pendingHeight: CGFloat?
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
            settingsWindow = SettingsWindow(model: model) { [weak self] in self?.settingsWindow = nil }
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
                guard let self, self.panel?.isVisible == true else { return }
                guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                    // SwiftUI reports the new height in the same pass that adds or removes controls, so the
                    // window grows or shrinks with them rather than a run-loop pass later. The animator
                    // starts on the next frame, so this never resizes the window inside SwiftUI's update.
                    self.positionPanel(contentHeight: height, animate: true)
                    return
                }
                // Without animation the window would resize and redraw inside SwiftUI's layout pass, which
                // re-entered it and left the panel at the wrong height with its content shifted. Resize once
                // the update finishes instead, to the latest height reported.
                let scheduled = self.pendingHeight != nil
                self.pendingHeight = height
                guard !scheduled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let height = self.pendingHeight else { return }
                    self.pendingHeight = nil
                    guard self.panel?.isVisible == true else { return }
                    self.positionPanel(contentHeight: height)
                }
            }))
            host.sizingOptions = []
            // `positionPanel` alone sizes the host, so window resizes never stretch it.
            host.view.autoresizingMask = []
            // No scroll view: the panel always fits its content, and scrolling only ever revealed empty
            // space. The flipped container keeps the content pinned to the top while the window's
            // bottom edge moves.
            let document = TopAnchoredView()
            document.addSubview(host.view)
            let container = NSViewController()
            container.view = MenuPanel.backdrop(containing: document)
            container.addChild(host)

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
    /// content. Pass `contentHeight` when SwiftUI has already measured it. With `animate`, the frame
    /// change follows the panel's own SwiftUI animation, keeping the top edge pinned under the icon.
    @discardableResult
    private func positionPanel(contentHeight: CGFloat? = nil, animate: Bool = false) -> Bool {
        guard let panel, let host, let button = item?.button,
              let menuWindow = button.window, let screen = menuWindow.screen else { return false }
        let anchor = menuWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let top = min(visible.maxY, anchor.minY - 6)
        guard top > visible.minY, visible.width > 0 else { return false }
        let width = min(350, visible.width)
        // The content is pinned to the top of a flexible frame, so propose no height to get its natural one.
        let natural = ceil(contentHeight ?? host.sizeThatFits(in: NSSize(width: width, height: 0)).height)
        guard natural > 0 else { return false }
        let available = top - visible.minY
        let height = min(natural, available)
        let x = min(max(anchor.midX - width / 2, visible.minX), visible.maxX - width)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        // Keep the host as tall as the panel can ever get, pinned to the top of the flipped container,
        // and let the window clip it. If the host were only the old content's height, SwiftUI would lay
        // the taller content out in it first, and the hosting view would center the overflow. Moving it
        // back once the new height arrived ran inside the mode change's animation, so the top of the
        // panel slid while it grew (#51).
        let hostFrame = NSRect(x: 0, y: 0, width: width, height: max(natural, available))
        if host.view.frame != hostFrame { host.view.frame = hostFrame }
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              panel.frame.height != height else {
            panel.setFrame(frame, display: true)
            return true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = GlowPanel.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
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
