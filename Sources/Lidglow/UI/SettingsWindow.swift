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

/// Chooses where Music mode listens: the chosen apps, all apps, or the microphone. The app checklist
/// opens in a sheet so the section stays short. Its list is gathered once when Settings opens: known
/// music apps that are installed, the apps already chosen, and apps that are running now.
private struct MusicSection: View {
    @ObservedObject var model: GlowModel
    @State private var apps = MusicApp.candidates()
    @State private var choosingApps = false

    var body: some View {
        Section {
            Picker("Listen to", selection: Binding(get: { model.musicSource },
                                                   set: { model.selectMusicSource($0) })) {
                ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
            }
            if model.musicSource == .chosenApps {
                LabeledContent("Apps") {
                    HStack(spacing: 10) {
                        Text(chosenSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Button("Choose…") { choosingApps = true }
                    }
                }
                .sheet(isPresented: $choosingApps) { MusicAppPicker(model: model, apps: apps) }
            }
            if model.microphoneDenied {
                LabeledContent {
                    Button("Open Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Text("Microphone access is off")
                    Text("Allow Lidglow under Privacy & Security → Microphone, then choose Microphone again.")
                }
            }
        } header: {
            Text("Music")
        } footer: {
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        switch model.musicSource {
        case .chosenApps:
            return "Music mode reacts only to the apps you choose. Safari plays audio through a shared system process, so choose All apps to follow it."
        case .allApps:
            return "Music mode reacts to everything your Mac plays, including system sounds, videos, and calls."
        case .microphone:
            return "Music mode reacts to sound around your Mac. The microphone stays on while Music is running, and macOS shows its indicator. It turns off when you switch modes, lock your Mac, or close the lid. Lidglow never records or saves what it hears."
        }
    }

    /// The chosen apps by name, in the list's order, for example "Spotify, Music, and 2 more".
    private var chosenSummary: String {
        let names = apps.filter { model.musicApps.contains($0.id) }.map(\.name)
        switch names.count {
        case 0: return "None"
        case 1...3: return names.joined(separator: ", ")
        default: return names.prefix(2).joined(separator: ", ") + ", and \(names.count - 2) more"
        }
    }
}

/// The checklist of apps Music listens to, shown as a sheet over Settings.
private struct MusicAppPicker: View {
    @ObservedObject var model: GlowModel
    let apps: [MusicApp]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
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
                } header: {
                    Text("Apps Music Listens To")
                } footer: {
                    Text("Installed music apps and the apps running now. Changes apply right away.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 440)
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
    static let releases = URL(string: "https://github.com/christhisway/Lidglow/releases")!
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
            LabeledContent {
                Link("View Releases", destination: ProjectLinks.releases)
            } label: {
                Text("Updates")
                Text("Lidglow doesn’t check for updates itself. New versions are posted on GitHub.")
            }
            Link("Read Me", destination: ProjectLinks.readme)
            Link("Source Code on GitHub", destination: ProjectLinks.repository)
        }
    }
}
