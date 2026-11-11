import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window, opened from the gear in the panel, ⌘, while the panel is focused, or the
/// menu-bar icon's context menu. Each setting adds its own section to `SettingsView`. It's built when
/// opened and released when closed, so it costs nothing while it isn't on screen.
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

    /// Lidglow is an accessory app with no main menu, so nothing else maps ⌘W to Close.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command && event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            GeneralSection()
            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 360)
    }
}

/// Open at Login, through the system's login item service for the app itself (macOS 13 and later).
private struct GeneralSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Section("General") {
            Toggle("Open at Login", isOn: Binding(get: { status == .enabled || status == .requiresApproval },
                                                  set: setOpenAtLogin))
            if status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                } label: {
                    Text("Needs your approval")
                    Text("Allow Lidglow in System Settings → General → Login Items.")
                }
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.secondary)
            }
        }
        // Approval happens in System Settings, so check again when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = "Couldn’t change Open at Login: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}

/// Lidglow has no network code, so these links only open pages in the user's browser.
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/christhisway/Lidglow")!
    static let readme = URL(string: "https://github.com/christhisway/Lidglow#readme")!
}

private struct AboutSection: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section("About") {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lidglow").font(.headline)
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Link("Read Me", destination: ProjectLinks.readme)
            Link("Source Code on GitHub", destination: ProjectLinks.repository)
        }
    }
}
