// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which part of the spectrum drives the glow in Music mode.
///
/// Bass, Mids, and Treble each listen to one narrow band with steep (24 dB per octave) filters:
/// kicks and bass notes at 40–120 Hz, the midrange where vocals, guitars, keys, and snares live at
/// 300 Hz–3 kHz, and cymbal sizzle above
/// 6 kHz. Each is a little tighter than the usual mixing ranges, so neighboring instruments leak in as
/// little as possible. A hit in one of these bands only counts when that band carries a real share of
/// the onset across the whole mix (see `share`), so a guitar strum's sliver of low end doesn't flash the
/// logo in Bass, and only when the band itself is loud enough (see `loudness`), so a quiet rumble such as
/// a breath in a vocal can't count as a hit just because it rose above an even quieter moment. Full is the original wide detector, unchanged.
enum EQPreset: String, CaseIterable {
    case bass = "Bass"
    case mids = "Mids"
    case treble = "Treble"
    case flat = "Full"

    /// Reads a saved preset, including names from earlier builds.
    init?(saved: String) {
        self.init(rawValue: saved == "Vocals" ? EQPreset.mids.rawValue : saved)
    }

    var detail: String {
        switch self {
        case .bass: "Kick drums and bass lines"
        case .mids: "Vocals, guitars, keys, and snares"
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
        /// How much this block's energy rose above the band's recent level.
        private(set) var transientEnergy: Float = 0

        mutating func onset(_ rms: Float, dt: Double) -> Float {
            // Compare this hit with the recent bed of sound in the same band.
            let reference = average * 1.12
            let transient = max(0, rms - reference)
            transientEnergy = max(0, rms * rms - reference * reference)
            peak = max(floor, transient, peak * Float(exp(-dt / 1.5)))
            let timeConstant = rms > average ? 0.16 : 0.30
            average += (rms - average) * Float(1 - exp(-dt / timeConstant))
            return min(1, gain * transient / peak)
        }
    }

    /// A second-order Butterworth section (RBJ cookbook). Two in a row make a 24 dB per octave slope.
    /// Doubles keep the low-frequency sections stable at 96 kHz.
    private struct Biquad {
        private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        private var z1 = 0.0, z2 = 0.0

        init(lowPass frequency: Double, sampleRate: Double) { self.init(frequency, sampleRate, highPass: false) }
        init(highPass frequency: Double, sampleRate: Double) { self.init(frequency, sampleRate, highPass: true) }

        private init(_ frequency: Double, _ sampleRate: Double, highPass: Bool) {
            let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
            let alpha = sin(w0) / (2 * 0.5.squareRoot())
            let cosine = cos(w0)
            let a0 = 1 + alpha
            let edge = highPass ? (1 + cosine) / 2 : (1 - cosine) / 2
            b0 = edge / a0
            b1 = (highPass ? -(1 + cosine) : 1 - cosine) / a0
            b2 = edge / a0
            a1 = -2 * cosine / a0
            a2 = (1 - alpha) / a0
        }

        mutating func callAsFunction(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    var preset = EQPreset.bass

    // Full: the original detector's one-pole filters and bands.
    private let bassCoefficient: Float
    private let rumbleCoefficient: Float
    private let drumCoefficient: Float
    private let trebleCoefficient: Float
    private var bassLowPass: Float = 0
    private var bassSmooth: Float = 0
    private var rumble: Float = 0
    private var drumLowPass: Float = 0
    private var trebleLowPass: (Float, Float, Float) = (0, 0, 0)
    private var bassBand = Band(floor: 0.004, gain: 1.35)
    private var drumBand = Band(floor: 0.009, gain: 1)
    private var trebleBand = Band(floor: 0.006, gain: 1)

    // Bass, Mids, and Treble: narrow bands, plus the whole mix to measure each band's share of a hit.
    private var kickFilters: [Biquad]
    private var voiceFilters: [Biquad]
    private var hatFilters: [Biquad]
    private var kickBand = Band(floor: 0.004, gain: 1.35)
    private var voiceBand = Band(floor: 0.006, gain: 1)
    private var hatBand = Band(floor: 0.004, gain: 1)
    private var mixBand = Band(floor: 0.001, gain: 1)

    private var envelope: Float = 0
    private let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bassCoefficient = Float(1 - exp(-2 * .pi * 165 / sampleRate))
        rumbleCoefficient = Float(1 - exp(-2 * .pi * 28 / sampleRate))
        drumCoefficient = Float(1 - exp(-2 * .pi * 2300 / sampleRate))
        trebleCoefficient = Float(1 - exp(-2 * .pi * 4000 / sampleRate))
        // Kick body and bass fundamentals sit around 50–100 Hz. Guitars and voices start near 80–120 Hz
        // but carry most of their energy well above, so stop at 120 Hz.
        kickFilters = [Biquad(highPass: 40, sampleRate: sampleRate),
                       Biquad(lowPass: 120, sampleRate: sampleRate), Biquad(lowPass: 120, sampleRate: sampleRate)]
        // The midrange: vocal formants, guitars, keys, and snare body and crack mostly sit at
        // 300 Hz–3 kHz, clear of kicks, bass, and most cymbal sizzle.
        voiceFilters = [Biquad(highPass: 300, sampleRate: sampleRate), Biquad(highPass: 300, sampleRate: sampleRate),
                        Biquad(lowPass: 3000, sampleRate: sampleRate), Biquad(lowPass: 3000, sampleRate: sampleRate)]
        // Hi-hat and cymbal sizzle is about 6–10 kHz and up. Starting at 6 kHz leaves out snare crack
        // and most vocal sibilance.
        hatFilters = [Biquad(highPass: 6000, sampleRate: sampleRate), Biquad(highPass: 6000, sampleRate: sampleRate)]
    }

    /// The fraction of the whole mix's onset energy that falls in this band, mapped so that under 10%
    /// counts for nothing and over 30% counts fully.
    private func share(_ band: Band) -> Float {
        let fraction = band.transientEnergy / max(mixBand.transientEnergy, band.transientEnergy, 1e-12)
        return min(1, max(0, (fraction - 0.10) / 0.20))
    }

    /// A minimum level for the band itself, in dB relative to full scale: nothing at `quiet`, fully at
    /// `loud`. Mastered kicks reach about -10 dBFS in their band, while a breath or room rumble sits
    /// around -40 dBFS or lower.
    private static func loudness(_ rms: Double, quiet: Double, loud: Double) -> Float {
        let decibels = 20 * log10(max(rms, 1e-9))
        return Float(min(1, max(0, (decibels - quiet) / (loud - quiet))))
    }

    mutating func process(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) -> Double {
        guard frames > 0, channels > 0 else { return 0 }
        var bassEnergy: Float = 0
        var drumEnergy: Float = 0
        var trebleEnergy: Float = 0
        var kickEnergy = 0.0
        var voiceEnergy = 0.0
        var hatEnergy = 0.0
        var mixEnergy = 0.0
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
            trebleLowPass.0 += (mono - trebleLowPass.0) * trebleCoefficient
            let trebleStage1 = mono - trebleLowPass.0
            trebleLowPass.1 += (trebleStage1 - trebleLowPass.1) * trebleCoefficient
            let trebleStage2 = trebleStage1 - trebleLowPass.1
            trebleLowPass.2 += (trebleStage2 - trebleLowPass.2) * trebleCoefficient
            let treble = trebleStage2 - trebleLowPass.2
            bassEnergy += bass * bass
            drumEnergy += drums * drums
            trebleEnergy += treble * treble

            // The narrow bands cost about 30 multiply-adds per sample. Filters keep running for every
            // preset so switching presets never starts a filter from silence, which would flash.
            let sample = Double(mono)
            var kick = sample
            for index in kickFilters.indices { kick = kickFilters[index](kick) }
            var voice = sample
            for index in voiceFilters.indices { voice = voiceFilters[index](voice) }
            var hat = sample
            for index in hatFilters.indices { hat = hatFilters[index](hat) }
            kickEnergy += kick * kick
            voiceEnergy += voice * voice
            hatEnergy += hat * hat
            mixEnergy += sample * sample
        }
        let dt = Double(frames) / sampleRate
        let count = Float(frames)
        let bass = bassBand.onset(sqrt(bassEnergy / count), dt: dt)
        let drums = drumBand.onset(sqrt(drumEnergy / count), dt: dt)
        let treble = trebleBand.onset(sqrt(trebleEnergy / count), dt: dt)
        _ = mixBand.onset(Float((mixEnergy / Double(frames)).squareRoot()), dt: dt)
        let kickLevel = (kickEnergy / Double(frames)).squareRoot()
        let voiceLevel = (voiceEnergy / Double(frames)).squareRoot()
        let hatLevel = (hatEnergy / Double(frames)).squareRoot()
        let kick = kickBand.onset(Float(kickLevel), dt: dt)
        let voice = voiceBand.onset(Float(voiceLevel), dt: dt)
        let hat = hatBand.onset(Float(hatLevel), dt: dt)
        let hit: Float
        switch preset {
        case .bass: hit = kick * share(kickBand) * Self.loudness(kickLevel, quiet: -40, loud: -28)
        case .mids: hit = voice * share(voiceBand) * Self.loudness(voiceLevel, quiet: -42, loud: -30)
        // Cymbals carry much less energy than kicks, so their floor sits lower.
        case .treble: hit = hat * share(hatBand) * Self.loudness(hatLevel, quiet: -48, loud: -36)
        case .flat: hit = max(bass, drums * 0.85, treble * 0.85)
        }
        envelope = max(hit, envelope * Float(exp(-dt / 0.095)))
        return Double(envelope)
    }
}
