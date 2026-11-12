// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The whole panel on a Mac with no light-up logo. It's static, so it never animates, observes the
/// model, or reports new heights, and Uninstall and Quit are its only controls.
struct UnsupportedPanel: View {
    /// Closes the panel, asks to confirm, then removes Lidglow and quits.
    let uninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Text("Lidglow").font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("This Mac doesn’t have a light-up Apple logo")
                    .font(.subheadline.weight(.semibold))
                Text("Lidglow controls the illuminated logo on MacBook Pro with PROLED XDR display, so it has nothing to control here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Divider()
            HStack {
                Spacer()
                Button("Uninstall…", action: uninstall).controlSize(.small)
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        // Pinned to the top of the tall host view, like `GlowPanel`.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
