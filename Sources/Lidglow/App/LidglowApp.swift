import AppKit
import Combine
import SwiftUI

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

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
            return
        }
        if panel == nil {
            let host = NSHostingController(rootView: GlowPanel(model: model))
            host.sizingOptions = []
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.documentView = host.view
            let container = NSViewController()
            container.view = MenuPanel.backdrop(containing: scroll)
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
        if let scroll = host?.view.enclosingScrollView, let document = scroll.documentView {
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
