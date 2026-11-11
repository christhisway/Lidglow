import Foundation

@main
enum BeatMeterCheck {
    struct Response { var steady = 0.0, kick = 0.0, snare = 0.0, hat = 0.0, silence = 0.0 }

    /// Feeds a bass and mid bed, a kick at 1 s, a snare at 2 s, a hi-hat at 3 s, then silence.
    static func run(_ preset: EQPreset, rate: Double) -> Response {
        let frames = Int(rate / 100)
        var samples = [Float](repeating: 0, count: frames)
        var meter = BeatMeter(sampleRate: rate)
        meter.preset = preset
        var response = Response()
        for block in 0..<425 {
            for frame in samples.indices {
                let t = Double(block * frames + frame) / rate
                let bassBed = 0.09 * sin(2 * .pi * 80 * t)
                let midBed = 0.025 * sin(2 * .pi * 850 * t)
                let kickTime = t - 1.0
                let snareTime = t - 2.0
                let hatTime = t - 3.0
                let kick = kickTime >= 0 ? 0.35 * exp(-kickTime / 0.034) * sin(2 * .pi * 65 * t) : 0
                let snare = snareTime >= 0 ? 0.17 * exp(-snareTime / 0.028) * sin(2 * .pi * 1100 * t) : 0
                let hat = hatTime >= 0 ? 0.10 * exp(-hatTime / 0.020) * sin(2 * .pi * 9000 * t) : 0
                samples[frame] = t < 3.6 ? Float(bassBed + midBed + kick + snare + hat) : 0
            }
            let level = samples.withUnsafeBufferPointer {
                meter.process($0.baseAddress!, frames: frames, channels: 1)
            }
            if (80..<100).contains(block) { response.steady = max(response.steady, level) }
            if (100..<108).contains(block) { response.kick = max(response.kick, level) }
            if (200..<208).contains(block) { response.snare = max(response.snare, level) }
            if (300..<308).contains(block) { response.hat = max(response.hat, level) }
            if block >= 418 { response.silence = max(response.silence, level) }
        }
        return response
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            for preset in EQPreset.allCases {
                let r = run(preset, rate: rate)
                print(Int(rate), preset.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0),
                      "steady", r.steady, "kick", r.kick, "snare", r.snare, "hat", r.hat, "silence", r.silence)
                precondition(r.steady < 0.08 && r.silence < 0.03, "\(preset) reacts to steady sound or silence")
                switch preset {
                case .bass:
                    // The original detector's behavior.
                    precondition(r.kick > 0.85 && r.snare > 0.35 && r.hat < 0.2)
                case .vocals:
                    precondition(r.snare > 0.85 && r.snare > r.kick * 2 && r.snare > r.hat * 2)
                case .treble:
                    precondition(r.hat > 0.85 && r.hat > r.kick * 2 && r.hat > r.snare * 2)
                case .flat:
                    precondition(r.kick > 0.85 && r.snare > 0.7 && r.hat > 0.7)
                }
            }
        }
    }
}
