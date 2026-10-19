import Charts
import SwiftUI

/// The popover: connection header, download/upload sparkline cards, usage totals and footer actions.
struct ContentView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.unitStyle) private var unitStyle: UnitStyle = .bytes
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ChartCard(title: "Download", color: .cyan, rate: monitor.downRate, unitStyle: unitStyle,
                      values: monitor.history.map { ($0.id, $0.down) })
            ChartCard(title: "Upload", color: .orange, rate: monitor.upRate, unitStyle: unitStyle,
                      values: monitor.history.map { ($0.id, $0.up) })
            totals
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.interfaceSymbol)
                .font(.title2)
                .foregroundStyle(monitor.isOnline ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.interfaceTitle).font(.headline)
                Text(monitor.localIP.map { "Local IP \($0)" } ?? (monitor.isOnline ? "No IPv4 address" : "Offline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Totals").font(.subheadline.bold()).gridColumnAlignment(.leading)
                    Text("↓ Down").foregroundStyle(.secondary)
                    Text("↑ Up").foregroundStyle(.secondary)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                totalsRow("Today", store.today)
                totalsRow("This Month", store.thisMonth)
                totalsRow("All Time", store.allTime)
            }
            .font(.callout.monospacedDigit())

            Button("Reset Counters") { confirmReset = true }
                .controlSize(.small)
                .confirmationDialog("Reset today's and all-time counters?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { store.resetCounters() }
                } message: {
                    Text("Earlier daily history is kept.")
                }
        }
    }

    private func totalsRow(_ title: String, _ usage: Usage) -> some View {
        GridRow {
            Text(title)
            Text(Format.bytes(usage.rx))
            Text(Format.bytes(usage.tx))
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Button("Support / Donate ❤️") { Support.openDonationPage() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

/// A card with the current rate and a sparkline of the last 60 seconds for one direction.
struct ChartCard: View {
    let title: String
    let color: Color
    let rate: Double?
    let unitStyle: UnitStyle
    let values: [(Int, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(rate.map { Format.rate($0, style: unitStyle) } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
            }
            if values.count < 2 {
                Text("Collecting data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Chart(values, id: \.0) { point in
                    AreaMark(x: .value("Sample", point.0), y: .value("Rate", scaled(point.1)))
                        .foregroundStyle(color.opacity(0.25))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Sample", point.0), y: .value("Rate", scaled(point.1)))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...max(1, values.map { scaled($0.1) }.max() ?? 1))
                .frame(height: 50)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func scaled(_ bytesPerSecond: Double) -> Double {
        unitStyle == .bits ? bytesPerSecond * 8 : bytesPerSecond
    }
}
