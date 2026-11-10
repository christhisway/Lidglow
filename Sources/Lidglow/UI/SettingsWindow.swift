import AppKit
import SwiftUI

/// The Settings window, opened from the menu-bar icon's context menu. It has no sections yet. Each
/// setting adds its own to `SettingsView`. It's built when opened and released when closed, so it
/// costs nothing while it isn't on screen.
final class SettingsWindow: NSWindow, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
                   styleMask: [.titled, .closable, .miniaturizable],
                   backing: .buffered, defer: true)
        title = "Lidglow Settings"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: SettingsView())
        delegate = self
        center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsWindow isn't loaded from a nib") }

    func windowWillClose(_ notification: Notification) { onClose() }
}

private struct SettingsView: View {
    var body: some View {
        Form {}
            .formStyle(.grouped)
            .frame(width: 500, height: 360)
    }
}
