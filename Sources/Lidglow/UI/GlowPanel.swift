import AppKit
import SwiftUI

struct GlowPanel: View {
    @ObservedObject var model: GlowModel
    var openSettings: () -> Void
    /// Reports the panel's natural height whenever it changes, during the same layout pass that adds or
    /// removes controls, so the window can resize along with them instead of a frame later.
    var onHeightChange: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resize: Animation? { reduceMotion ? nil : .easeInOut(duration: Self.resizeDuration) }
    static let resizeDuration = 0.22
    private let reveal = AnyTransition.opacity

    var body: some View {
        content
            // Take the natural height whatever the window's current height, and report it. The host view
            // is always at least as tall as the panel can get, so the content never overflows it and is
            // never centered while the height changes.
            .fixedSize(horizontal: false, vertical: true)
            // A height preference read through a background GeometryReader only reported once in a
            // hosting controller sized by hand, so use a geometry observer, which fires on every change.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
            // Pin the content to the top of the tall host view, so the space below it stays empty and the
            // window's bottom edge reveals or clips it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                Text("Lidglow").font(.headline)
                Spacer(minLength: 12)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
                Toggle("Control the lid logo", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(model.enabled ? "Turn off to let macOS control the lid logo"
                                        : "Turn on to control the lid logo with Lidglow")
            }
            LaptopPreview(level: model.enabled ? model.level : 0.65, isVisible: model.panelVisible)
            VStack(alignment: .leading, spacing: 15) {
                GlassSegments(items: GlowMode.allCases, selection: model.mode, select: model.select) { mode in
                    VStack(spacing: 5) {
                        Image(systemName: mode.icon).font(.system(size: 14, weight: .medium))
                        Text(mode.rawValue).font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                control("Brightness", icon: "sun.max", value: $model.brightness, range: model.brightnessRange,
                        reading: model.brightness > 0 ? "\(Int((model.brightness * 100).rounded()))%" : "Off")
                if model.mode == .breathe {
                    choice("Speed", icon: "gauge.with.dots.needle.50percent", items: BreatheSpeed.allCases,
                           selection: model.breatheSpeed, select: { model.breatheSpeed = $0 }) {
                        "\($0.rawValue) breathing speed"
                    }
                    .transition(reveal)
                }
                if model.mode == .music {
                    musicControls.transition(reveal)
                }
            }
            // While macOS has the logo, the modes and their settings stay visible but inactive.
            .disabled(!model.enabled)
            .opacity(model.enabled ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.2), value: model.enabled)
            Divider()
            HStack {
                Text(model.status)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(model.status)
                Spacer(minLength: 12)
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
            if model.mode == .music {
                Button(model.musicSource == .microphone ? "Microphone Settings…" : "System Audio Settings…") {
                    model.openAudioSettings()
                }
                    .buttonStyle(.link).font(.subheadline)
                    .transition(reveal)
            }
        }
        // The window animates to the new height over the same duration (see `LidglowApp.positionPanel`).
        .animation(resize, value: model.mode)
        .animation(resize, value: model.idleGlow)
        .padding(18)
        .frame(maxWidth: .infinity)
    }

    private var musicControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            choice("Focus", icon: "slider.vertical.3", items: EQPreset.allCases,
                   selection: model.eqPreset, select: { model.eqPreset = $0 }) {
                "\($0.rawValue): \($0.detail)"
            }
            control("Sensitivity", icon: "waveform", value: $model.sensitivity, range: 0.4...2.0,
                    reading: String(format: "%.1f×", model.sensitivity))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Idle glow", isOn: $model.idleGlow).toggleStyle(.switch).controlSize(.small)
                if model.idleGlow {
                    control("Idle brightness", icon: "moon", value: $model.idleBrightness,
                            range: model.idleBrightnessRange,
                            reading: "\(Int((model.idleBrightness * 100).rounded()))%")
                        .disabled(model.brightness == 0)
                        .transition(reveal)
                }
            }
        }
    }

    /// A compact glass selector for a small set of options, such as Breathe's speed.
    private func choice<Item: Hashable & RawRepresentable<String>>(
        _ title: String, icon: String, items: [Item], selection: Item, select: @escaping (Item) -> Void,
        describe: @escaping (Item) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)
            GlassSegments(items: items, selection: selection, select: select) { item in
                Text(item.rawValue)
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .help(describe(item))
                    .accessibilityLabel(describe(item))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func control(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>,
                         reading: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(reading)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: value, in: range) { Text(title) }
                .labelsHidden()
                .controlSize(.large)
                .tint(Color.primary.opacity(0.65))
                .accessibilityValue(Text(reading))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
