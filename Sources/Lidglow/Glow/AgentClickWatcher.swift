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

    /// The app an agent runs in, found by walking up from the agent's process to the first ancestor that's a
    /// regular app with a Dock icon. The agent is usually a helper or command-line process: Codex's
    /// bundled CLI under the ChatGPT app, Claude Code under the Claude app, or a shell under Terminal or
    /// VS Code. Nil when no ancestor is an app, for example under tmux, whose server has no app parent.
    static func hostApp(ofProcess pid: pid_t) -> String? {
        var current = pid
        for _ in 0..<32 {
            guard current > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular,
               let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                return id
            }
            guard let parent = parentProcess(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

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
