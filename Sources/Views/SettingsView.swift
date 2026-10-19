import ServiceManagement
import SwiftUI

/// Settings window: launch at login, units, interval, counted interfaces, menu bar mode and history reset.
struct SettingsView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @AppStorage(SettingsKey.unitStyle) private var unitStyle: UnitStyle = .bytes
    @AppStorage(SettingsKey.interval) private var interval: Double = 1
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .both
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Picker("Units", selection: $unitStyle) {
                    ForEach(UnitStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Update interval", selection: $interval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                .onChange(of: interval) { _, _ in monitor.restartTimer() }
                Picker("Menu bar shows", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                if monitor.interfaces.isEmpty {
                    Text("No interfaces found").foregroundStyle(.secondary)
                }
                ForEach(monitor.interfaces) { option in
                    Toggle(isOn: Binding(get: { monitor.isCounted(option.name) },
                                         set: { monitor.setCounted(option.name, $0) })) {
                        HStack {
                            Text(option.displayName)
                            Text(option.name).foregroundStyle(.secondary).font(.caption.monospaced())
                            if !option.isActive {
                                Text("inactive").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("Counted interfaces")
            } footer: {
                Text("Turn off VPN tunnels (utun…) and bridges to avoid counting the same traffic twice. Loopback is never counted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                HStack {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonationPage() }
                }
                Text("Totals are stored locally for \(UsageStore.retentionDays) days. No packets are inspected and nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .confirmationDialog("Delete all stored usage history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { monitor.clearHistory() }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). You can manage it in System Settings › General › Login Items."
        }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            loginError = "Approve NetPulseBar in System Settings › General › Login Items."
        }
        let actual = status == .enabled || status == .requiresApproval
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}
