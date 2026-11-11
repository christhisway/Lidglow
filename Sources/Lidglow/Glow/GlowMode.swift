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
