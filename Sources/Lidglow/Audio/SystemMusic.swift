import CoreAudio
import Foundation

final class SystemMusic {
    struct TapError: LocalizedError {
        var operation: String
        var status: OSStatus
        var errorDescription: String? { "\(operation) failed (\(status)). Check System Audio Recording permission, then try again." }
    }

    /// Which apps Music listens to. `nil` taps all system audio.
    var bundleIDs: Set<String>? = ["com.spotify.client", "com.apple.Music"] {
        didSet { if started && bundleIDs != oldValue { rebuild() } }
    }
    /// Called on the main queue when rebuilding the tap after a change fails.
    var onFailure: ((Error) -> Void)?
    /// Music mode wants audio. The tap itself only exists while a selected app has audio.
    private(set) var started = false
    /// Music mode is on, but none of the selected apps has audio open, so there's no tap.
    var waitingForApps: Bool { started && callback == nil }
    private var tappedProcesses: [AudioObjectID]?
    private var processListener: AudioObjectPropertyListenerBlock?
    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var latest = (time: 0.0, level: 0.0)
    private var wakeArmed = false
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

    /// Starts listening. With selected apps, the tap is built when one of them has audio open and
    /// rebuilt as they come and go, from Core Audio's own process list notification, never polling.
    func start() throws {
        guard !started else { return }
        started = true
        if bundleIDs != nil { watchProcesses(true) }
        do { try buildTap() } catch { stop(); throw error }
    }

    private func watchProcesses(_ on: Bool) {
        if on, processListener == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processesChanged() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.processListAddress,
                                                   .main, listener) == noErr {
                processListener = listener
            }
        } else if !on, let listener = processListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.processListAddress,
                                                   .main, listener)
            processListener = nil
        }
    }

    private func processesChanged() {
        guard started, let bundleIDs, matchingProcesses(bundleIDs) != tappedProcesses else { return }
        rebuild()
    }

    private func rebuild() {
        teardownTap()
        watchProcesses(bundleIDs != nil)
        do { try buildTap() } catch {
            stop()
            onFailure?(error)
        }
    }

    /// Core Audio's process objects for the selected apps, including their helpers (for example
    /// `com.google.Chrome.helper`), in a stable order.
    private func matchingProcesses(_ bundleIDs: Set<String>) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &Self.processListAddress, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &Self.processListAddress, 0, nil, &size, &processes) == noErr else {
            return []
        }
        return processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).filter { process in
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &address, 0, nil, &nameSize, &name) == noErr,
                  let id = name?.takeRetainedValue() as String? else { return false }
            return bundleIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
        }.sorted()
    }

    private func buildTap() throws {
        let processes = bundleIDs.map(matchingProcesses)
        tappedProcesses = processes
        // None of the selected apps has audio open. Stay down until the process list changes.
        if processes?.isEmpty == true { return }
        do {
            let description = processes.map { CATapDescription(monoMixdownOfProcesses: $0) }
                ?? CATapDescription(monoGlobalTapButExcludeProcesses: [])
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
                let wake = self.wakeArmed && level > Self.soundThreshold
                if wake { self.wakeArmed = false }
                self.lock.unlock()
                if wake { DispatchQueue.main.async { [weak self] in self?.onSound?() } }
            }, "Audio callback")
            try check(AudioDeviceStart(device, callback), "System audio")
        } catch {
            teardownTap()
            throw error
        }
    }

    func level(at now: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return now - latest.time < 0.25 ? latest.level : 0
    }

    func stop() {
        started = false
        watchProcesses(false)
        teardownTap()
    }

    private func teardownTap() {
        tappedProcesses = nil
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
