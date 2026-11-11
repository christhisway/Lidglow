// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Reports which app owns the window under each mouse click, so a click in the app an agent runs in can
/// stop that agent's pulse even when the app is already in front. It runs only while a pulse waits on a
/// known app. Watching mouse clicks in other apps needs no permission (keystrokes would), and reading a
/// window's owner needs no Screen Recording permission. It learns nothing else: not the window's title or
/// contents, not where in the window the click landed, and never anything typed.
final class AgentClickWatcher {
    /// Called on the main thread with the bundle ID of the clicked window's app.
    var onClick: ((String) -> Void)?
    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in self?.clicked()
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit { stop() }

    private func clicked() {
        // The topmost window at the pointer, from any app, then its owner. Only the owner's process ID is
        // read from the window list.
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        guard number > 0,
              let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]],
              let pid = info.first?[kCGWindowOwnerPID as String] as? pid_t,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return }
        onClick?(bundleID)
    }
}
