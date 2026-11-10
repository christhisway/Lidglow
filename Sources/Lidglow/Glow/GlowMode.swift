enum GlowMode: String, CaseIterable {
    case system = "System"
    case off = "Off"
    case steady = "Steady"
    case breathe = "Breathe"
    case music = "Music"

    var icon: String {
        switch self {
        case .system: "sparkle"
        case .off: "circle"
        case .steady: "sun.max"
        case .breathe: "wind"
        case .music: "waveform"
        }
    }
}
