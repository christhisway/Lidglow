// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit.ps
import os

/// Whether the internal battery is charging, from IOKit's power source info. Being plugged in with a full
/// battery doesn't count. IOKit's power source notification reports every change, so nothing polls, and
/// the watch runs only between `start()` and `stop()`.
final class PowerSource {
    private(set) var isCharging = false
    /// Called on the main thread when `isCharging` changes while watching.
    var onChange: ((Bool) -> Void)?
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue().update()
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Logger.hardware.error("Couldn't watch the power source, so charging won't change the glow")
            return
        }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        update()
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
        isCharging = false
    }

    deinit { stop() }

    private func update() {
        let charging = Self.readCharging()
        guard charging != isCharging else { return }
        isCharging = charging
        Logger.hardware.notice("Battery \(charging ? "started" : "stopped", privacy: .public) charging")
        onChange?(charging)
    }

    /// True when an internal battery reports `kIOPSIsChargingKey`.
    private static func readCharging() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any] else { return false }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
                && description[kIOPSIsChargingKey] as? Bool == true
        }
    }
}
