// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Settings → Agents. Agent alerts aren't a mode: the pulse plays over whichever mode is selected, then
/// hands the logo back to it. Lidglow never edits an agent's config itself. Each agent's Set Up… sheet
/// shows the hooks to paste in.
struct AgentsSection: View {
    @ObservedObject var model: GlowModel
    @State private var settingUp: CodingAgent?

    var body: some View {
        Section {
            Toggle(isOn: $model.agentAlerts) {
                Text("Pulse when an agent needs you")
                Text("Coding agents can pulse the lid logo while they wait for you, whatever mode is selected.")
            }
            if model.agentAlerts {
                ForEach(CodingAgent.allCases) { agent in
                    LabeledContent {
                        HStack(spacing: 10) {
                            Button("Set Up…") { settingUp = agent }
                            Toggle(agent.title, isOn: alerting(agent))
                                .labelsHidden()
                        }
                    } label: {
                        Text(agent.title)
                        Text("Hooks in \(agent.configPath)")
                    }
                }
                Toggle(isOn: $model.agentAlertsOnFinish) {
                    Text("Also pulse when an agent finishes")
                    Text("Otherwise only permission prompts and questions pulse the logo.")
                }
                Toggle(isOn: $model.agentAlertsWhileOff) {
                    Text("Pulse even when Lidglow is off")
                    Text("Takes the logo from macOS for each pulse while the panel's switch is off, then hands it straight back.")
                }
                LabeledContent {
                    Slider(value: $model.agentAlertBrightness, in: 0.05...1) { Text("Pulse brightness") }
                        .labelsHidden()
                        .frame(width: 160)
                        .accessibilityValue(Text("\(Int((model.agentAlertBrightness * 100).rounded()))%"))
                } label: {
                    Text("Pulse brightness")
                    Text("\(Int((model.agentAlertBrightness * 100).rounded()))%")
                }
                Picker("Stop pulsing after", selection: $model.agentAlertTimeout) {
                    ForEach(AgentAlertTimeout.allCases) { Text($0.title).tag($0) }
                }
            }
        } header: {
            Text("Agents")
        } footer: {
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $settingUp) { AgentSetupSheet(agent: $0) }
    }

    private var footer: String {
        guard model.agentAlerts else {
            return "Agents tell Lidglow only that they need you or finished, never what they're working on."
        }
        let switchNote = model.agentAlertsWhileOff
            ? "It plays whether Lidglow's switch is on or off"
            : "It plays only while Lidglow's switch is on"
        return "The pulse stops when you reply to the agent, open the Lidglow panel, or after the time above. \(switchNote), and pauses like any mode when you lock your Mac or close the lid. Agents tell Lidglow only that they need you or finished, never what they're working on."
    }

    private func alerting(_ agent: CodingAgent) -> Binding<Bool> {
        Binding(get: { model.alertingAgents.contains(agent) }, set: { on in
            if on { model.alertingAgents.insert(agent) } else { model.alertingAgents.remove(agent) }
        })
    }
}

/// The hooks for one agent, to copy into its config by hand.
private struct AgentSetupSheet: View {
    let agent: CodingAgent
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Up \(agent.title)").font(.headline)
            Text(agent.instructions)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView([.vertical, .horizontal]) {
                Text(agent.hookSnippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Each hook does nothing unless Lidglow is running, and sends only the agent's name and whether it needs you, finished, or is working again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? "Copied" : "Copy Hooks") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(agent.hookSnippet, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520, height: 470)
    }
}
