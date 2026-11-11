// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Liquid Glass surfaces shared by the panel's controls, kept in one place so other surfaces
/// (such as a mode-cycle HUD) can match them. Reduce Transparency swaps the system glass for an opaque
/// control fill, and Increase Contrast adds an outline. Both settings are read from the environment, so the surface follows them live.
private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        surface(content).contrastOutline(shape)
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
        } else {
            content.glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
        }
    }
}

private struct ContrastOutline<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

extension View {
    /// Places the view on a Liquid Glass surface in `shape`.
    func glassSurface<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive))
    }

    /// Outlines `shape` when Increase Contrast is on, for fills that are too faint to read as edges.
    func contrastOutline<S: InsettableShape>(_ shape: S) -> some View {
        modifier(ContrastOutline(shape: shape))
    }
}

/// A row of segments whose selection is a glass lens. When the selection changes, the lens slides
/// to the new segment with a bouncy spring. Pressing a segment gives it a slight squeeze, and pressing
/// the selected segment swells its lens, the way the system's Liquid Glass selectors respond.
struct GlassSegments<Item: Hashable, SegmentLabel: View>: View {
    let items: [Item]
    let selection: Item
    let select: (Item) -> Void
    @ViewBuilder let label: (Item) -> SegmentLabel
    @Namespace private var lens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button { select(item) } label: { label(item) }
                    .buttonStyle(GlassSegmentStyle(selected: item == selection, lens: lens))
                    .accessibilityAddTraits(item == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.primary.opacity(0.06), in: Capsule())
        .contrastOutline(Capsule())
        .animation(reduceMotion ? nil : .bouncy(duration: 0.38, extraBounce: 0.12), value: selection)
    }
}

private struct GlassSegmentStyle: ButtonStyle {
    let selected: Bool
    let lens: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        return configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(pressed && !selected ? 0.94 : 1)
            .background {
                if selected {
                    Color.clear
                        .glassSurface(in: Capsule(), interactive: true)
                        .scaleEffect(pressed ? 1.05 : 1)
                        .matchedGeometryEffect(id: "lens", in: lens)
                }
            }
            .contentShape(Capsule())
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: pressed)
    }
}
