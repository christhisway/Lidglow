import AppKit
import SwiftUI

struct GlowPanel: View {
    @ObservedObject var model: GlowModel
    var openSettings: () -> Void
    var body: some View {
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
                control("Brightness", icon: "sun.max", value: $model.brightness, range: 0...1,
                        reading: model.brightness > 0 ? "\(Int((model.brightness * 100).rounded()))%" : "Off")
                if model.mode == .breathe {
                    speedControl
                }
                if model.mode == .music {
                    control("Sensitivity", icon: "waveform", value: $model.sensitivity, range: 0.4...2.0,
                            reading: String(format: "%.1f×", model.sensitivity))
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Idle glow", isOn: $model.idleGlow).toggleStyle(.switch).controlSize(.small)
                        if model.idleGlow {
                            control("Idle brightness", icon: "moon", value: $model.idleBrightness,
                                    range: model.idleBrightnessRange,
                                    reading: "\(Int((model.idleBrightness * 100).rounded()))%")
                                .disabled(model.brightness == 0)
                        }
                    }
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
                Button("System Audio Settings…") { model.openAudioSettings() }
                    .buttonStyle(.link).font(.subheadline)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Speed", systemImage: "gauge.with.dots.needle.50percent")
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)
            GlassSegments(items: BreatheSpeed.allCases, selection: model.breatheSpeed,
                          select: { model.breatheSpeed = $0 }) { speed in
                Text(speed.rawValue)
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityLabel("\(speed.rawValue) breathing speed")
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
