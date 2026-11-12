// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement
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
            GeneralSection(model: model)
            MusicSection(model: model)
            AgentsSection(model: model)
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
            if model.musicSource != .microphone {
                Toggle(isOn: $model.autoMusic) {
                    Text("Automatically switch to Music")
                    Text(model.musicSource == .chosenApps ? "Switches to Music when a chosen app starts playing."
                                                          : "Switches to Music when any app starts playing.")
                }
            }
            Picker(selection: $model.musicTimeout) {
                ForEach(MusicTimeout.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Switch back after silence")
                Text(switchBackExplainer)
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
            return "Music mode reacts to everything your apps play, including videos and calls. System sounds such as alerts and volume feedback are ignored."
        case .microphone:
            return "Music mode reacts to sound around your Mac. The microphone stays on while Music is running, and macOS shows its indicator. It turns off when you switch modes, lock your Mac, or close the lid. Lidglow never records or saves what it hears. Automatic switching to Music needs Chosen apps or All apps."
        }
    }

    private var switchBackExplainer: String {
        switch model.musicTimeout {
        case .automatic where model.musicSource == .chosenApps:
            return "Returns to the mode you used before Music when the audio stream from all chosen apps stops."
        case .automatic where model.musicSource == .allApps:
            return "Returns to the mode you used before Music when every app's audio stream stops."
        case .automatic:
            return "Automatically follows apps' audio streams, so with the microphone Music returns to your previous mode after 10 seconds of silence."
        case .never:
            return "Music stays on until you pick another mode."
        default:
            return "Returns to the mode you used before Music once nothing has played for this long."
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

/// Open at Login, through the system's login item service for the app itself (macOS 13 and later), and
/// Breathe while charging.
private struct GeneralSection: View {
    @ObservedObject var model: GlowModel
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
            Toggle(isOn: $model.breatheWhileCharging) {
                Text("Breathe while charging")
                Text("Every mode breathes while the battery charges, except Music while music plays.")
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

/// These links open pages in the user's browser. Lidglow itself never loads them.
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/christhisway/Lidglow")!
    static let readme = URL(string: "https://github.com/christhisway/Lidglow#readme")!
    static let releases = URL(string: "https://github.com/christhisway/Lidglow/releases")!
    static let license = URL(string: "https://github.com/christhisway/Lidglow/blob/main/LICENSE")!
}

private struct AboutSection: View {
    @ObservedObject private var updater = Updater.shared

    private var isBeta: Bool {
        !((Bundle.main.infoDictionary?["LidglowReleaseLabel"] as? String) ?? "").isEmpty
    }

    private var updateStatus: String {
        switch updater.state {
        case .idle:
            return "Installs the latest stable release from GitHub if it’s newer, then reopens Lidglow. Lidglow only connects when you click."
        case .checking:
            return "Checking GitHub for a newer stable release…"
        case .upToDate where isBeta:
            return "There’s no newer stable release. Newer betas are listed under View Releases."
        case .upToDate:
            return "Lidglow is up to date."
        case .noStableRelease:
            return "There’s no stable release yet. Betas are listed under View Releases."
        case .installing:
            return "Installing the update. Lidglow will quit and reopen."
        case .failed(let reason):
            return reason
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        // A pre-release names its stage after the version, for example "0.9.0 Beta (2)". A stable release
        // leaves `LidglowReleaseLabel` out of Info.plist.
        if let label = info?["LidglowReleaseLabel"] as? String, !label.isEmpty {
            return "\(short) \(label) (\(build))"
        }
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
                HStack(spacing: 8) {
                    if updater.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check for Updates") { updater.check() }
                        .disabled(updater.isBusy)
                }
            } label: {
                Text("Updates")
                Text(updateStatus)
            }
            Link("View Releases", destination: ProjectLinks.releases)
            Link("Read Me", destination: ProjectLinks.readme)
            Link("Source Code on GitHub", destination: ProjectLinks.repository)
            LabeledContent {
                Link("View License", destination: ProjectLinks.license)
            } label: {
                Text("License")
                Text("Free software under the GNU GPL v3 or later, with no warranty. Not affiliated with Apple. Created by Jayden Webb and Kunal Singh.")
            }
        }
    }
}
