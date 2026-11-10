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
