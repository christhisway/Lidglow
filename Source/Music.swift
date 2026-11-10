import CoreAudio
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

final class SystemMusic {
    struct TapError: LocalizedError {
        var operation: String
        var status: OSStatus
        var errorDescription: String? { "\(operation) failed (\(status)). Check System Audio Recording permission, then try again." }
    }

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var latest = (time: 0.0, level: 0.0)
    var running: Bool { callback != nil }

    func start() throws {
        guard !running else { return }
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
            description.name = "Lidglow Music"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap), "Audio tap")

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: format))
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Tap format")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
                throw TapError(operation: "Tap format", status: kAudioHardwareUnsupportedOperationError)
            }

            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Lidglow Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
                ]
            ]
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &device), "Audio device")

            var meter = BeatMeter(sampleRate: format.mSampleRate)
            try check(AudioDeviceCreateIOProcIDWithBlock(&callback, device, nil) { [weak self] _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let buffer = buffers.first(where: { $0.mData != nil }), let data = buffer.mData,
                      buffer.mNumberChannels > 0 else { return }
                let channels = Int(buffer.mNumberChannels)
                let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                let level = meter.process(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
                guard let self, self.lock.try() else { return }
                self.latest = (ProcessInfo.processInfo.systemUptime, level)
                self.lock.unlock()
            }, "Audio callback")
            try check(AudioDeviceStart(device, callback), "System audio")
        } catch {
            stop()
            throw error
        }
    }

    func level(at now: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return now - latest.time < 0.25 ? latest.level : 0
    }

    func stop() {
        if let callback {
            AudioDeviceStop(device, callback)
            AudioDeviceDestroyIOProcID(device, callback)
        }
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        callback = nil
        device = kAudioObjectUnknown
        tap = kAudioObjectUnknown
        lock.lock()
        latest = (0, 0)
        lock.unlock()
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw TapError(operation: operation, status: status) }
    }
}
