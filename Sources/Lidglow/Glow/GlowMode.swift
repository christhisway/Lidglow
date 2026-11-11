enum GlowMode: String, CaseIterable {
    case standard = "Standard"
    case breathe = "Breathe"
    case music = "Music"

    var icon: String {
        switch self {
        case .standard: "sun.max"
        case .breathe: "wind"
        case .music: "waveform"
        }
    }
}

/// How fast Breathe mode breathes. The depth is the same at every speed. Breathe while charging
/// always uses `normal`, whatever is selected here.
enum BreatheSpeed: String, CaseIterable {
    case slow = "Slow"
    case normal = "Normal"
    case fast = "Fast"

    /// Seconds per full breath. Starting points to tune on real hardware.
    var period: Double {
        switch self {
        case .slow: 8
        case .normal: 5
        case .fast: 3
        }
    }
}

/// How long Music waits through silence before switching back to the mode used before it.
enum MusicTimeout: Int, CaseIterable, Identifiable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case never = 0

    var id: Int { rawValue }

    /// Seconds of silence before switching back, or nil for never.
    var seconds: Double? { self == .never ? nil : Double(rawValue) }

    var title: String {
        switch self {
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .fifteenSeconds: "15 seconds"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .never: "Never"
        }
    }
}
