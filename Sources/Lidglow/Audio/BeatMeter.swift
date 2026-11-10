import Foundation

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

    private let bassCoefficient: Float
    private let rumbleCoefficient: Float
    private let drumCoefficient: Float
    private var bassLowPass: Float = 0
    private var bassSmooth: Float = 0
    private var rumble: Float = 0
    private var drumLowPass: Float = 0
    private var bassBand = Band(floor: 0.004, gain: 1.35)
    private var drumBand = Band(floor: 0.009, gain: 1)
    private var envelope: Float = 0
    private let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bassCoefficient = Float(1 - exp(-2 * .pi * 165 / sampleRate))
        rumbleCoefficient = Float(1 - exp(-2 * .pi * 28 / sampleRate))
        drumCoefficient = Float(1 - exp(-2 * .pi * 2300 / sampleRate))
    }

    mutating func process(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) -> Double {
        guard frames > 0, channels > 0 else { return 0 }
        var bassEnergy: Float = 0
        var drumEnergy: Float = 0
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
            bassEnergy += bass * bass
            drumEnergy += drums * drums
        }
        let dt = Double(frames) / sampleRate
        let bass = bassBand.onset(sqrt(bassEnergy / Float(frames)), dt: dt)
        let drums = drumBand.onset(sqrt(drumEnergy / Float(frames)), dt: dt)
        let hit = max(bass, drums * 0.50)
        envelope = max(hit, envelope * Float(exp(-dt / 0.095)))
        return Double(envelope)
    }
}
