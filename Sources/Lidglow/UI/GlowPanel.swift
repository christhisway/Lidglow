import AppKit
import SwiftUI

struct GlowPanel: View {
    @ObservedObject var model: GlowModel
    private let accent = Color(red: 0.48, green: 0.91, blue: 0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2).foregroundStyle(accent)
                Text("Lidglow").font(.headline)
                Spacer()
                Text("LID LIGHT").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
            }
            preview
            HStack(spacing: 4) {
                ForEach(GlowMode.allCases, id: \.self) { mode in
                    Button { model.select(mode) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: mode.icon).font(.system(size: 14, weight: .medium))
                            Text(mode.rawValue).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(model.mode == mode ? accent : .secondary)
                        .background(model.mode == mode ? accent.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
            }
            .padding(4)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            if model.mode == .music || model.mode == .steady || model.mode == .breathe {
                control("Brightness", value: $model.brightness, range: 0.05...1,
                        reading: "\(Int((model.brightness * 100).rounded()))%")
            }
            if model.mode == .music {
                control("Sensitivity", value: $model.sensitivity, range: 0.4...2.0,
                        reading: String(format: "%.1f×", model.sensitivity))
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Idle glow", isOn: $model.idleGlow).toggleStyle(.switch).controlSize(.small)
                    if model.idleGlow {
                        control("Idle brightness", value: $model.idleBrightness, range: model.idleBrightnessRange,
                                reading: "\(Int((model.idleBrightness * 100).rounded()))%")
                        Text("Amber preview · The lid LED glows white")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
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
        .padding(16)
        .frame(maxWidth: .infinity)
        .preferredColorScheme(.dark)
    }

    private var preview: some View {
        let glow = model.mode == .system ? 0.65 : model.level
        let amber = Color(red: 1, green: 0.65, blue: 0.24)
        let previewColor = model.mode == .music && model.idleGlow ? amber : .white
        let haloColor = model.mode == .music && model.idleGlow ? amber : accent
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.055, green: 0.07, blue: 0.09))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.075))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.105)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)) }
                .frame(width: 152, height: 90)
            Image(systemName: "apple.logo")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(previewColor.opacity(0.14 + glow * 0.86))
                .shadow(color: haloColor.opacity(glow * 0.82), radius: 8)
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                         reading: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(reading).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).tint(accent).accessibilityLabel(title)
        }
    }
}
