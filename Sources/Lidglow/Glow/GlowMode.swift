enum GlowMode: String, CaseIterable {
    case system = "System"
    case standard = "Standard"
    case breathe = "Breathe"
    case music = "Music"

    var icon: String {
        switch self {
        case .system: "sparkle"
        case .standard: "sun.max"
        case .breathe: "wind"
        case .music: "waveform"
        }
    }
}
