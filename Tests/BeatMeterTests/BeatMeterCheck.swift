import Foundation

@main
enum BeatMeterCheck {
    static func main() {
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            let frames = Int(rate / 100)
            var samples = [Float](repeating: 0, count: frames)
            var meter = BeatMeter(sampleRate: rate)
            var kick = 0.0, snare = 0.0, sustained = 0.0, tail = 0.0
            for block in 0..<325 {
                for frame in samples.indices {
                    let t = Double(block * frames + frame) / rate
                    let bassBed = 0.09 * sin(2 * .pi * 80 * t)
                    let midBed = 0.025 * sin(2 * .pi * 850 * t)
                    let kickTime = t - 1.0
                    let snareTime = t - 2.0
                    let kickSample = kickTime >= 0 ? 0.35 * exp(-kickTime / 0.034) * sin(2 * .pi * 65 * t) : 0
                    let snareSample = snareTime >= 0 ? 0.17 * exp(-snareTime / 0.028) * sin(2 * .pi * 1100 * t) : 0
                    samples[frame] = t < 2.6 ? Float(bassBed + midBed + kickSample + snareSample) : 0
                }
                let level = samples.withUnsafeBufferPointer {
                    meter.process($0.baseAddress!, frames: frames, channels: 1)
                }
                if (80..<100).contains(block) { sustained = max(sustained, level) }
                if (100..<108).contains(block) { kick = max(kick, level) }
                if (200..<208).contains(block) { snare = max(snare, level) }
                if block >= 318 { tail = max(tail, level) }
            }
            print(Int(rate), "steady", sustained, "kick", kick, "snare", snare, "silence", tail)
            precondition(sustained < 0.08 && kick > 0.85 && snare > 0.35 && tail < 0.03)
        }
    }
}
