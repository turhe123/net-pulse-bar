import AppKit
import SwiftUI

/// App entry point: a menu-bar-only app with a window-style popover and a Settings scene.
@main
struct NetPulseBarApp: App {
    @StateObject private var monitor = NetworkMonitor()

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.unitStyle: UnitStyle.bytes.rawValue,
            SettingsKey.interval: 1.0,
            SettingsKey.displayMode: DisplayMode.both.rawValue,
        ])
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(monitor.store)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(monitor.store)
        }
    }
}

/// The menu bar text: live rates in a monospaced-digit font, a dash before the first sample, or "Offline".
struct MenuBarLabel: View {
    @ObservedObject var monitor: NetworkMonitor
    @AppStorage(SettingsKey.unitStyle) private var unitStyle: UnitStyle = .bytes
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .both

    var body: some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
    }

    private var text: String {
        guard monitor.isOnline else { return "Offline" }
        guard let down = monitor.downRate, let up = monitor.upRate else { return "—" }
        let downText = "↓" + Format.rate(down, style: unitStyle)
        let upText = "↑" + Format.rate(up, style: unitStyle)
        switch displayMode {
        case .both: return downText + " " + upText
        case .download: return downText
        case .upload: return upText
        }
    }
}

/// Opens the project's donation page in the default browser.
enum Support {
    static func openDonationPage() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
