// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit

enum LaptopFinish: String {
    case silver = "Silver"
    case spaceBlack = "Space Black"

    static let current = detected ?? .silver

    static let detected: LaptopFinish? = {
        let chosen = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard chosen != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(chosen) }

        guard let data = IORegistryEntryCreateCFProperty(chosen, "housing-color" as CFString, nil, 0)?
            .takeRetainedValue() as? Data, data.count == 16 else { return nil }

        // This firmware record stores a 32-bit format marker and a finish code at byte 12.
        let (format, code) = data.withUnsafeBytes {
            (UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)),
             UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)))
        }
        guard format == 1 else { return nil }
        // Verified against the Space Black PROLED XDR MacBook Pro. Unmapped finishes use Silver.
        return code == 9 ? .spaceBlack : nil
    }()
}
