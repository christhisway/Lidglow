// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Coding agents that can ask Lidglow to pulse the logo through their hooks. Only these names are
/// accepted from a `lidglow://` link, so another app opening one can at worst make the logo pulse.
enum CodingAgent: String, CaseIterable, Identifiable {
    case claudeCode = "claude-code"
    case codex = "codex"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Where the hooks below go.
    var configPath: String {
        switch self {
        case .claudeCode: "~/.claude/settings.json"
        case .codex: "~/.codex/hooks.json"
        }
    }

    /// The setup steps shown above the snippet in Settings.
    var instructions: String {
        switch self {
        case .claudeCode:
            "Add these hooks to \(configPath). If the file already has a \"hooks\" object, merge these events into it. Claude Code picks up the change in new sessions."
        case .codex:
            "Add these hooks to \(configPath), merging them into any hooks already there. Then run /hooks in Codex to review and trust them. Codex runs hooks only after you trust them."
        }
    }

    /// The shell command a hook runs. It does nothing unless Lidglow is already running, so an agent never
    /// launches it, and it always succeeds, so the agent never reports a hook error. `open -g` delivers
    /// the link without bringing anything to the front.
    func hookCommand(_ signal: AgentSignal) -> String {
        "pgrep -qx Lidglow && open -g 'lidglow://agent/\(signal.rawValue)?agent=\(rawValue)' || true"
    }

    /// The exact hooks to paste into the agent's config. Each event maps to one signal:
    /// - Claude Code's `Notification` fires a few seconds into a permission prompt, after about a minute
    ///   waiting for a reply, or when it asks a question. Codex's `PermissionRequest` fires when it's
    ///   about to ask for approval.
    /// - `Stop` fires when a turn finishes.
    /// - `UserPromptSubmit` (you replied) and `PostToolUse` (a tool ran, for example after an approval)
    ///   mean the agent is working again. `PostToolUse` runs after every tool call, so it's async and
    ///   never slows the agent down.
    var hookSnippet: String {
        let waiting: String
        switch self {
        case .claudeCode:
            waiting = """
                "Notification": [
                  {
                    "matcher": "permission_prompt|idle_prompt|elicitation_dialog|agent_needs_input",
                    "hooks": [{ "type": "command", "command": "\(hookCommand(.attention))" }]
                  }
                ],
            """
        case .codex:
            waiting = """
                "PermissionRequest": [
                  { "hooks": [{ "type": "command", "command": "\(hookCommand(.attention))" }] }
                ],
            """
        }
        return """
        {
          "hooks": {
        \(waiting)
            "Stop": [
              { "hooks": [{ "type": "command", "command": "\(hookCommand(.done))" }] }
            ],
            "UserPromptSubmit": [
              { "hooks": [{ "type": "command", "command": "\(hookCommand(.clear))" }] }
            ],
            "PostToolUse": [
              { "hooks": [{ "type": "command", "command": "\(hookCommand(.clear))", "async": true }] }
            ]
          }
        }
        """
    }
}

/// What an agent can tell Lidglow. Nothing else is accepted, and nothing about the agent's work comes
/// with it: no prompt, file, or project.
enum AgentSignal: String {
    /// The agent is waiting on you: a permission prompt, a question, or no reply for a while.
    case attention
    /// The agent finished a turn. It pulses only with Settings → Agents → Also pulse when an agent finishes.
    case done
    /// The agent is working again, so its pulse stops.
    case clear
}

/// A `lidglow://agent/<signal>?agent=<name>` link from an agent hook. Any app can open a `lidglow://`
/// link, so anything that isn't exactly this shape, with a known signal and agent, is rejected.
struct AgentRequest: Equatable {
    let signal: AgentSignal
    let agent: CodingAgent

    init?(url: URL) {
        guard url.scheme?.lowercased() == "lidglow", url.host()?.lowercased() == "agent",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              url.pathComponents.count == 2,
              let signal = AgentSignal(rawValue: url.pathComponents[1]),
              let query = parts.queryItems, query.count == 1, query[0].name == "agent",
              let agent = query[0].value.flatMap(CodingAgent.init(rawValue:)) else { return nil }
        self.signal = signal
        self.agent = agent
    }
}

/// How long an agent's pulse lasts if nothing clears it first.
enum AgentAlertTimeout: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case never = 0

    var id: Int { rawValue }

    /// Seconds before the pulse stops on its own, or nil for never.
    var seconds: Double? { rawValue > 0 ? Double(rawValue) : nil }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }
}

enum AgentPulse {
    /// One cycle of the pulse, in seconds.
    static let period = 2.0

    /// Whether the pulse is lit `elapsed` seconds after it started. Normally a quick double pulse every two
    /// seconds, unlike Breathe's slow wave or Music's beats. With Reduce Motion it's one gentler pulse a
    /// cycle, with slower fades (see `fades(reduceMotion:)`). Starts lit, so a new alert shows right away.
    static func isLit(elapsed: Double, reduceMotion: Bool) -> Bool {
        let phase = elapsed.truncatingRemainder(dividingBy: period)
        if reduceMotion { return phase < 0.8 }
        return phase < 0.25 || (phase >= 0.5 && phase < 0.75)
    }

    /// Rise and fall times for `LidLogo.follow`. Starting points to tune on real hardware.
    static func fades(reduceMotion: Bool) -> (rise: Double, fall: Double) {
        reduceMotion ? (0.35, 0.5) : (0.08, 0.12)
    }
}
