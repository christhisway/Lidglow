import Foundation

/// Which part of the spectrum drives the glow in Music mode. Each preset weights the onsets of four
/// bands: bass (about 28–165 Hz), drums (the original wide 165–2300 Hz band), mids (a narrower
/// 300–2300 Hz band that rejects kicks), and treble (above about 4 kHz, which rejects snares).
enum EQPreset: String, CaseIterable {
    case bass = "Bass"
    case vocals = "Vocals"
    case treble = "Treble"
    case flat = "Full"

    var weights: (bass: Float, drums: Float, mids: Float, treble: Float) {
        switch self {
        // Bass is the original detector: kicks lead and snares count for half.
        case .bass: (1, 0.50, 0, 0)
        case .vocals: (0.30, 0, 1, 0.25)
        case .treble: (0.20, 0, 0.35, 1)
        case .flat: (1, 0.85, 0, 0.85)
        }
    }

    var detail: String {
        switch self {
        case .bass: "Kick drums and bass lines"
        case .vocals: "Vocals, snares, and melody"
        case .treble: "Hi-hats and cymbals"
        case .flat: "The whole mix"
        }
    }
}

struct BeatMeter {
    private struct Band {
        var floor: Float
        var gain: Float
        var average: Float = 0
        var peak: Float = 0

        mutating func onset(_ rms: Float, dt: Double) -> Float {
            // Compare this hit with the recent bed of sound in the same band.
            let transient = max(0, rms - average * 1.12)
            peak = max(floor, transient, peak * Float(exp(-dt / 1.5)))
            let timeConstant = rms > average ? 0.16 : 0.30
            average += (rms - average) * Float(1 - exp(-dt / timeConstant))
            return min(1, gain * transient / peak)
        }
    }

    var preset = EQPreset.bass
    private let bassCoefficient: Float
    private let rumbleCoefficient: Float
    private let drumCoefficient: Float
    private let midCoefficient: Float
    private let trebleCoefficient: Float
    private var bassLowPass: Float = 0
    private var bassSmooth: Float = 0
    private var rumble: Float = 0
    private var drumLowPass: Float = 0
    private var midLowPass: (Float, Float) = (0, 0)
    private var trebleLowPass: (Float, Float, Float) = (0, 0, 0)
    private var bassBand = Band(floor: 0.004, gain: 1.35)
    private var drumBand = Band(floor: 0.009, gain: 1)
    private var midBand = Band(floor: 0.009, gain: 1)
    private var trebleBand = Band(floor: 0.006, gain: 1)
    private var envelope: Float = 0
    private let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bassCoefficient = Float(1 - exp(-2 * .pi * 165 / sampleRate))
        rumbleCoefficient = Float(1 - exp(-2 * .pi * 28 / sampleRate))
        drumCoefficient = Float(1 - exp(-2 * .pi * 2300 / sampleRate))
        midCoefficient = Float(1 - exp(-2 * .pi * 300 / sampleRate))
        trebleCoefficient = Float(1 - exp(-2 * .pi * 4000 / sampleRate))
    }

    mutating func process(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) -> Double {
        guard frames > 0, channels > 0 else { return 0 }
        var bassEnergy: Float = 0
        var drumEnergy: Float = 0
        var midEnergy: Float = 0
        var trebleEnergy: Float = 0
        for frame in 0..<frames {
            var mono: Float = 0
            for channel in 0..<channels { mono += samples[frame * channels + channel] }
            mono /= Float(channels)
            guard mono.isFinite else { continue }
            bassLowPass += (mono - bassLowPass) * bassCoefficient
            bassSmooth += (bassLowPass - bassSmooth) * bassCoefficient
            rumble += (bassSmooth - rumble) * rumbleCoefficient
            drumLowPass += (mono - drumLowPass) * drumCoefficient
            let bass = bassSmooth - rumble
            let drums = drumLowPass - bassLowPass
            // Two high-pass stages for mids and three for treble give the steeper slopes that keep a
            // kick out of the mids and a snare out of the treble.
            midLowPass.0 += (drumLowPass - midLowPass.0) * midCoefficient
            let midStage = drumLowPass - midLowPass.0
            midLowPass.1 += (midStage - midLowPass.1) * midCoefficient
            let mids = midStage - midLowPass.1
            trebleLowPass.0 += (mono - trebleLowPass.0) * trebleCoefficient
            let trebleStage1 = mono - trebleLowPass.0
            trebleLowPass.1 += (trebleStage1 - trebleLowPass.1) * trebleCoefficient
            let trebleStage2 = trebleStage1 - trebleLowPass.1
            trebleLowPass.2 += (trebleStage2 - trebleLowPass.2) * trebleCoefficient
            let treble = trebleStage2 - trebleLowPass.2
            bassEnergy += bass * bass
            drumEnergy += drums * drums
            midEnergy += mids * mids
            trebleEnergy += treble * treble
        }
        let dt = Double(frames) / sampleRate
        let bass = bassBand.onset(sqrt(bassEnergy / Float(frames)), dt: dt)
        let drums = drumBand.onset(sqrt(drumEnergy / Float(frames)), dt: dt)
        let mids = midBand.onset(sqrt(midEnergy / Float(frames)), dt: dt)
        let treble = trebleBand.onset(sqrt(trebleEnergy / Float(frames)), dt: dt)
        let weights = preset.weights
        let hit = max(bass * weights.bass, drums * weights.drums, mids * weights.mids, treble * weights.treble)
        envelope = max(hit, envelope * Float(exp(-dt / 0.095)))
        return Double(envelope)
    }
}
