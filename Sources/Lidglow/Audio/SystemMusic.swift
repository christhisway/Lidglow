import CoreAudio
import Foundation
import os

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
    private var wakeArmed = false
    private var requestedPreset = EQPreset.bass
    var running: Bool { callback != nil }
    /// Meter level above which the glow treats audio as music rather than silence.
    static let soundThreshold = 0.035
    /// Called on the main queue the first time sound crosses the threshold after `armWake()`.
    var onSound: (() -> Void)?

    /// Lets the glow loop tick slowly during silence without missing the first beat.
    func armWake() {
        lock.lock()
        wakeArmed = true
        lock.unlock()
    }

    /// Which part of the spectrum drives the level. The audio callback picks it up on its next buffer.
    var preset: EQPreset {
        get { lock.lock(); defer { lock.unlock() }; return requestedPreset }
        set { lock.lock(); requestedPreset = newValue; lock.unlock() }
    }

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
            meter.preset = preset
            try check(AudioDeviceCreateIOProcIDWithBlock(&callback, device, nil) { [weak self] _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let buffer = buffers.first(where: { $0.mData != nil }), let data = buffer.mData,
                      buffer.mNumberChannels > 0 else { return }
                let channels = Int(buffer.mNumberChannels)
                let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                let level = meter.process(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
                guard let self, self.lock.try() else { return }
                self.latest = (ProcessInfo.processInfo.systemUptime, level)
                // The callback never waits on the lock, so a preset change applies from the next buffer.
                meter.preset = self.requestedPreset
                let wake = self.wakeArmed && level > Self.soundThreshold
                if wake { self.wakeArmed = false }
                self.lock.unlock()
                if wake { DispatchQueue.main.async { [weak self] in self?.onSound?() } }
            }, "Audio callback")
            try check(AudioDeviceStart(device, callback), "System audio")
            Logger.audio.notice("System audio tap started at \(format.mSampleRate) Hz")
        } catch {
            Logger.audio.error("System audio tap failed: \(error.localizedDescription, privacy: .public)")
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
        if callback != nil { Logger.audio.notice("System audio tap stopped") }
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
        wakeArmed = false
        lock.unlock()
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw TapError(operation: operation, status: status) }
    }
}
