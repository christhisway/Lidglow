import AppKit
import SwiftUI

/// The Settings window, opened from the gear in the panel, ⌘, while the panel is focused, or the
/// menu-bar icon's context menu. Each setting adds its own section to `SettingsView`. It's built when
/// opened and released when closed, so it costs nothing while it isn't on screen.
final class SettingsWindow: NSWindow, NSWindowDelegate {
    private let onClose: () -> Void

    init(model: GlowModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                   styleMask: [.titled, .closable, .miniaturizable],
                   backing: .buffered, defer: true)
        title = "Lidglow Settings"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: SettingsView(model: model))
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
    @ObservedObject var model: GlowModel

    var body: some View {
        Form {
            MusicSection(model: model)
            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
    }
}

/// Chooses which apps Music mode reacts to. The list is gathered once when Settings opens: known music
/// apps that are installed, the apps already chosen, and apps that are running now.
private struct MusicSection: View {
    @ObservedObject var model: GlowModel
    @State private var apps = MusicApp.candidates()

    var body: some View {
        Section {
            Toggle("React to all apps", isOn: $model.listenToAllApps)
            if !model.listenToAllApps {
                ForEach(apps) { app in
                    Toggle(isOn: chosen(app.id)) {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(app.name)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text("Music")
        } footer: {
            Text(model.listenToAllApps
                 ? "Music mode reacts to everything your Mac plays, including system sounds, videos, and calls."
                 : "Music mode reacts only to the apps checked here. Safari plays audio through a shared system process, so turn on React to all apps to follow it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func chosen(_ id: String) -> Binding<Bool> {
        Binding(get: { model.musicApps.contains(id) }, set: { on in
            if on {
                if !model.musicApps.contains(id) { model.musicApps.append(id) }
            } else {
                model.musicApps.removeAll { $0 == id }
            }
        })
    }
}

private struct MusicApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage

    /// Music players that are offered whenever they're installed, in this order.
    private static let known = ["com.spotify.client", "com.apple.Music", "com.tidal.desktop", "com.amazon.music",
                                "com.deezer.deezer-desktop", "com.apple.podcasts", "com.google.Chrome",
                                "com.microsoft.edgemac", "org.mozilla.firefox"]

    static func candidates() -> [MusicApp] {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.filter { $0.activationPolicy == .regular }
        let chosen = UserDefaults.standard.stringArray(forKey: "musicApps") ?? GlowModel.defaultMusicApps
        var ids: [String] = []
        for id in known + chosen
            + running.compactMap(\.bundleIdentifier).sorted()
            where !ids.contains(id) && id != Bundle.main.bundleIdentifier {
            ids.append(id)
        }
        return ids.compactMap { id in
            if let url = workspace.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path)
                return MusicApp(id: id, name: name.replacingOccurrences(of: ".app", with: ""),
                                icon: workspace.icon(forFile: url.path))
            }
            // Keep a chosen app that has since been removed, so it can be unchecked.
            guard chosen.contains(id),
                  let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) else {
                return nil
            }
            return MusicApp(id: id, name: id, icon: fallback)
        }
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
