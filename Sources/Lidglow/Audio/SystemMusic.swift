// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import CoreAudio
import Foundation
import os

/// Where Music mode listens, as chosen in Settings → Music.
enum MusicSource: String, CaseIterable, Identifiable {
    case chosenApps, allApps, microphone
    var id: Self { self }
    var title: String {
        switch self {
        case .chosenApps: return "Chosen apps"
        case .allApps: return "All apps"
        case .microphone: return "Microphone"
        }
    }
}

/// Music mode's sound source: the chosen apps' playback, all system audio, or, only when the user picks it,
/// the microphone. Either way the samples are reduced to a level on the audio thread and discarded.
final class SystemMusic {
    struct TapError: LocalizedError {
        var operation: String
        var status: OSStatus
        var errorDescription: String? { "\(operation) failed (\(status)). Check System Audio Recording permission, then try again." }
    }

    struct MicrophoneError: LocalizedError {
        var errorDescription: String?
    }

    enum Source: Equatable {
        /// Only these apps' playback, including their helper processes.
        case apps(Set<String>)
        /// Everything apps play. macOS's own system sounds (alerts, volume feedback) are left out.
        case allApps
        /// The default input device.
        case microphone
    }

    var source = Source.apps(["com.spotify.client", "com.apple.Music"]) {
        didSet { if started && source != oldValue { rebuild() } }
    }
    /// The selected apps, or `nil` when Music doesn't follow particular apps.
    private var bundleIDs: Set<String>? {
        if case .apps(let ids) = source { return ids }
        return nil
    }
    /// Called on the main queue when rebuilding the tap after a change fails.
    var onFailure: ((Error) -> Void)?
    /// Music mode wants audio. The tap itself only exists while a selected app has audio.
    private(set) var started = false
    /// Music mode is on, but none of the selected apps has audio open, so there's no tap.
    var waitingForApps: Bool { started && bundleIDs != nil && callback == nil }
    /// The process list the tap was built from: the apps it includes, or with All apps the system
    /// processes it excludes. A change rebuilds the tap.
    private var tappedProcesses: [AudioObjectID]?
    private var processListener: AudioObjectPropertyListenerBlock?
    static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private var microphone: AVAudioEngine?
    private var microphoneObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var latest = (time: 0.0, level: 0.0)
    private var wakeArmed = false
    private var requestedPreset = EQPreset.bass
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

    /// Starts listening. With selected apps, the tap is built when one of them has audio open and
    /// rebuilt as they come and go, from Core Audio's own process list notification, never polling.
    /// With the microphone, the input stays open until `stop()`, which the model calls whenever Music
    /// pauses (lock, sleep, lid closed) or another mode is chosen.
    func start() throws {
        guard !started else { return }
        started = true
        if source != .microphone { watchProcesses(true) }
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
        guard started, source != .microphone, tapProcesses() != tappedProcesses else { return }
        rebuild()
    }

    private func rebuild() {
        teardownTap()
        watchProcesses(source != .microphone)
        do { try buildTap() } catch {
            stop()
            onFailure?(error)
        }
    }

    /// Core Audio's process objects for the selected apps, including their helpers (for example
    /// `com.google.Chrome.helper`), in a stable order. `PlaybackWatcher` uses the same matching.
    static func processes(matching bundleIDs: Set<String>) -> [AudioObjectID] {
        guard !bundleIDs.isEmpty else { return [] }
        return allProcesses().filter { process in
            guard let id = bundleID(of: process) else { return false }
            return bundleIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
        }
    }

    /// The processes the tap is built from: the selected apps to include, or with All apps the system
    /// processes to exclude.
    private func tapProcesses() -> [AudioObjectID] {
        bundleIDs.map(Self.processes(matching:)) ?? Self.allProcesses().filter { !Self.isAppAudio($0) }
    }

    /// Apple's own media helpers that carry app playback: WebKit plays Safari's (and other web views')
    /// audio in its GPU process.
    private static let appleMediaHelpers: Set<String> = ["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"]

    /// Whether a process plays on behalf of an app, for All apps. That's any third-party process, any
    /// regular Apple app (Music, TV, QuickTime Player, FaceTime), and WebKit's media helpers. It leaves out
    /// Lidglow itself, whose tap runs audio input while Music is on, and macOS's system processes, which
    /// play alerts, volume-change feedback (`com.apple.MediaRemoteUIService`), and other interface sounds
    /// (`systemsoundserverd` and the like). Processes without a reverse-DNS bundle ID are system daemons.
    static func isAppAudio(_ process: AudioObjectID) -> Bool {
        guard let pid = pid(of: process), pid != ProcessInfo.processInfo.processIdentifier,
              let id = bundleID(of: process), id.contains(".") else { return false }
        if !id.hasPrefix("com.apple.") || appleMediaHelpers.contains(id) { return true }
        return NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    /// Every process Core Audio knows about, in a stable order.
    static func allProcesses() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &Self.processListAddress, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &Self.processListAddress, 0, nil, &size, &processes) == noErr else {
            return []
        }
        return processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).sorted()
    }

    static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func pid(of process: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    private func buildTap() throws {
        if source == .microphone {
            tappedProcesses = nil
            try buildMicrophone()
            return
        }
        let processes = tapProcesses()
        tappedProcesses = processes
        // None of the selected apps has audio open. Stay down until the process list changes.
        if bundleIDs != nil && processes.isEmpty { return }
        do {
            // All apps taps everything except macOS's system sounds, so alerts and volume feedback never
            // reach the light.
            let description = bundleIDs != nil ? CATapDescription(monoMixdownOfProcesses: processes)
                                               : CATapDescription(monoGlobalTapButExcludeProcesses: processes)
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
                self?.publish(level, meter: &meter)
            }, "Audio callback")
            try check(AudioDeviceStart(device, callback), "System audio")
            Logger.audio.notice("System audio tap started at \(format.mSampleRate) Hz")
        } catch {
            Logger.audio.error("System audio tap failed: \(error.localizedDescription, privacy: .public)")
            teardownTap()
            throw error
        }
    }

    /// Opens the default input device. The model only selects this source once macOS has granted
    /// microphone access, but access can be revoked later, so check again.
    private func buildMicrophone() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MicrophoneError(errorDescription: "Microphone access is off. Allow Lidglow under Privacy & Security → Microphone, then try again.")
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneError(errorDescription: "No microphone is available.")
        }
        var meter = BeatMeter(sampleRate: format.sampleRate)
        meter.preset = preset
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // The first channel is enough for a level, and works for mono and stereo inputs alike.
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let level = meter.process(samples, frames: Int(buffer.frameLength), channels: 1)
            self?.publish(level, meter: &meter)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Logger.audio.error("Microphone input failed: \(error.localizedDescription, privacy: .public)")
            throw MicrophoneError(errorDescription: "Couldn't start the microphone (\(error.localizedDescription)).")
        }
        microphone = engine
        // A new default input (headphones plugged in, for example) stops the engine. Rebuild on it.
        microphoneObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.started, self.source == .microphone else { return }
            self.rebuild()
        }
        Logger.audio.notice("Microphone input started at \(format.sampleRate) Hz")
    }

    /// Hands a new level to the glow loop. Runs on the audio thread and never waits on the lock, so a
    /// busy main thread can't stall audio. A preset change reaches the meter from the next buffer.
    private func publish(_ level: Double, meter: inout BeatMeter) {
        guard lock.try() else { return }
        latest = (ProcessInfo.processInfo.systemUptime, level)
        meter.preset = requestedPreset
        let wake = wakeArmed && level > Self.soundThreshold
        if wake { wakeArmed = false }
        lock.unlock()
        if wake { DispatchQueue.main.async { [weak self] in self?.onSound?() } }
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
        if let microphoneObserver { NotificationCenter.default.removeObserver(microphoneObserver) }
        microphoneObserver = nil
        if let microphone {
            microphone.inputNode.removeTap(onBus: 0)
            microphone.stop()
            Logger.audio.notice("Microphone input stopped")
        }
        microphone = nil
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
