// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Foundation
import os

/// Tells whether any of the chosen music apps, or with All apps any app, is playing, for switching into
/// and out of Music automatically.
/// It reads Core Audio's per-process `kAudioProcessPropertyIsRunning`, which says whether a process has
/// audio I/O running. That is "playing" as opposed to "silent", so quiet passages don't count as stopped.
/// `kAudioProcessPropertyIsRunningOutput` would be more precise, but on macOS 27 its listeners never fire
/// (reading it works), so Lidglow only ever saw the state at launch. `IsRunning` notifies on play and,
/// about 2 s later, on pause. It needs no tap and never touches audio. Everything is driven by property
/// listeners on the process objects and on the process list, with no polling.
final class PlaybackWatcher {
    /// Apps to watch, matched with their helpers exactly as Music's tap matches them. Nil watches every
    /// app (see `otherApps()`).
    var bundleIDs: Set<String>? = [] {
        didSet { if watching && bundleIDs != oldValue { refresh() } }
    }
    /// Called on the main queue when `playing` changes.
    var onChange: ((Bool) -> Void)?
    /// At least one watched process has audio running.
    private(set) var playing = false

    private var watching = false
    private var listListener: AudioObjectPropertyListenerBlock?
    private var watched: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunning,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Starts watching. If a chosen app is already playing, `onChange` is called before this returns.
    func start() {
        guard !watching else { return }
        watching = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &SystemMusic.processListAddress,
                                               .main, listener) == noErr {
            listListener = listener
        }
        refresh()
    }

    /// Stops watching and forgets the playing state, without calling `onChange`.
    func stop() {
        guard watching else { return }
        watching = false
        if let listListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &SystemMusic.processListAddress,
                                                   .main, listListener)
        }
        listListener = nil
        for (process, listener) in watched {
            AudioObjectRemovePropertyListenerBlock(process, &Self.runningAddress, .main, listener)
        }
        watched = [:]
        playing = false
    }

    /// Follows apps as they open and close audio, then rechecks whether any of them is playing.
    private func refresh() {
        guard watching else { return }
        let processes = Set(bundleIDs.map(SystemMusic.processes(matching:)) ?? Self.otherApps())
        for (process, listener) in watched where !processes.contains(process) {
            // A process that has gone away has already dropped its listeners, so a failure here is fine.
            AudioObjectRemovePropertyListenerBlock(process, &Self.runningAddress, .main, listener)
            watched[process] = nil
        }
        for process in processes where watched[process] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.update() }
            if AudioObjectAddPropertyListenerBlock(process, &Self.runningAddress, .main, listener) == noErr {
                watched[process] = listener
            }
        }
        update()
    }

    private func update() {
        guard watching else { return }
        let now = watched.keys.contains(where: Self.isRunning)
        guard now != playing else { return }
        playing = now
        Logger.audio.notice("\(self.bundleIDs == nil ? "Apps" : "Chosen music apps", privacy: .public) \(now ? "started" : "stopped", privacy: .public) playing")
        onChange?(now)
    }

    /// For All apps: every process that plays on behalf of an app, the same set the All apps tap hears
    /// (`SystemMusic.isAppAudio`). Runs only when the process list changes.
    private static func otherApps() -> [AudioObjectID] {
        SystemMusic.allProcesses().filter(SystemMusic.isAppAudio)
    }

    private static func isRunning(_ process: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &size, &running) == noErr
            && running != 0
    }
}
