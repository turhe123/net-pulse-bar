import Foundation

/// Whether rates are shown in bytes (MB/s) or bits (Mbps) per second.
enum UnitStyle: String, CaseIterable, Identifiable {
    case bytes, bits
    var id: String { rawValue }
    var title: String { self == .bytes ? "Bytes per second (MB/s)" : "Bits per second (Mbps)" }
}

/// Which directions the menu bar label shows.
enum DisplayMode: String, CaseIterable, Identifiable {
    case both, download, upload
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: return "Download and upload"
        case .download: return "Download only"
        case .upload: return "Upload only"
        }
    }
}

/// UserDefaults keys shared by the views and the monitor.
enum SettingsKey {
    static let unitStyle = "unitStyle"
    static let interval = "updateInterval"
    static let displayMode = "displayMode"
    static let interfaceChoices = "interfaceChoices"
}

/// Converts byte counts and rates to fixed-width, human-readable strings.
enum Format {
    private static let figureSpace: Character = "\u{2007}"

    /// A rate padded to a constant character count so the menu bar label does not jitter.
    static func rate(_ bytesPerSecond: Double, style: UnitStyle) -> String {
        let units = style == .bits ? ["bps", "Kbps", "Mbps", "Gbps"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, style == .bits ? bytesPerSecond * 8 : bytesPerSecond)
        var index = 0
        while value >= 999.5 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let number = (index > 0 && value < 9.95) ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return pad(number, to: 3, leading: true) + " " + pad(units[index], to: 4, leading: false)
    }

    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .decimal)
    }

    private static func pad(_ text: String, to width: Int, leading: Bool) -> String {
        let padding = String(repeating: figureSpace, count: max(0, width - text.count))
        return leading ? padding + text : text + padding
    }
}
