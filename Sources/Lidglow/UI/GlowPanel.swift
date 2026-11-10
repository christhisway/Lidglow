import AppKit
import SwiftUI

struct GlowPanel: View {
    @ObservedObject var model: GlowModel
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                Text("Lidglow").font(.headline)
            }
            LaptopPreview(level: model.mode == .system ? 0.65 : model.level,
                           isVisible: model.panelVisible)
            GlassSegments(items: GlowMode.allCases, selection: model.mode, select: model.select) { mode in
                VStack(spacing: 5) {
                    Image(systemName: mode.icon).font(.system(size: 14, weight: .medium))
                    Text(mode.rawValue).font(.system(size: 10, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            if model.mode != .system {
                control("Brightness", icon: "sun.max", value: $model.brightness, range: 0...1,
                        reading: model.brightness > 0 ? "\(Int((model.brightness * 100).rounded()))%" : "Off")
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
            Divider()
            HStack {
                Text(model.status)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(model.status)
                Spacer(minLength: 12)
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
            if model.mode == .music {
                Button("System Audio Settings…") { model.openAudioSettings() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
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
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 14))
    }
}
