import AppKit
import Foundation
import Network

/// Samples interface counters on a timer, computes live rates and a 60-second history,
/// tracks connectivity with `NWPathMonitor`, and feeds byte deltas into the `UsageStore`.
@MainActor
final class NetworkMonitor: ObservableObject {
    /// One point of the sparkline history.
    struct Point: Identifiable {
        let id: Int
        let down: Double
        let up: Double
    }

    /// An interface the user can include or exclude in Settings.
    struct InterfaceOption: Identifiable, Equatable {
        let name: String
        let displayName: String
        let isActive: Bool
        var id: String { name }
    }

    @Published private(set) var downRate: Double?
    @Published private(set) var upRate: Double?
    @Published private(set) var history: [Point] = []
    @Published private(set) var isOnline = true
    @Published private(set) var interfaceTitle = "No active connection"
    @Published private(set) var interfaceSymbol = "network.slash"
    @Published private(set) var localIP: String?
    @Published private(set) var interfaces: [InterfaceOption] = []
    @Published private(set) var choices: [String: Bool]

    let store = UsageStore()

    private var previous: [String: InterfaceSnapshot] = [:]
    private var previousTime: TimeInterval?
    private var discardNextSample = true
    private var timer: Timer?
    private var nextPointID = 0
    private var lastSave = Date()
    private var primaryInterface: String?
    private var displayNames = InterfaceReader.displayNames()
    private let pathMonitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    var interval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: SettingsKey.interval)
        return [1, 2, 5].contains(value) ? value : 1
    }

    private var historyCapacity: Int { max(2, Int(60 / interval)) }

    init() {
        choices = UserDefaults.standard.dictionary(forKey: SettingsKey.interfaceChoices) as? [String: Bool] ?? [:]
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.apply(path) }
        }
        pathMonitor.start(queue: .main)
        observeSystemEvents()
        restartTimer()
        tick()
    }

    /// Re-creates the sampling timer, e.g. after the update interval changes.
    func restartTimer() {
        timer?.invalidate()
        history = []
        discardNextSample = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func isCounted(_ name: String) -> Bool {
        choices[name] ?? InterfaceReader.countedByDefault(name)
    }

    func setCounted(_ name: String, _ counted: Bool) {
        choices[name] = counted
        UserDefaults.standard.set(choices, forKey: SettingsKey.interfaceChoices)
    }

    func clearHistory() {
        store.clearHistory()
        history = []
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let snapshot = InterfaceReader.snapshot()
        refreshInterfaceList(snapshot)
        defer {
            previous = snapshot
            previousTime = now
        }
        guard let previousTime, !discardNextSample else {
            discardNextSample = false
            return
        }
        let elapsed = now - previousTime
        guard elapsed > 0.25 else { return }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, current) in snapshot where current.isActive && !current.isLoopback && isCounted(name) {
            // Interfaces that just appeared have no baseline yet; they count from the next sample.
            guard let old = previous[name] else { continue }
            rx += InterfaceReader.delta(old: old.inBytes, new: current.inBytes)
            tx += InterfaceReader.delta(old: old.outBytes, new: current.outBytes)
        }

        let down = Double(rx) / elapsed
        let up = Double(tx) / elapsed
        downRate = down
        upRate = up
        store.add(rx: rx, tx: tx)

        history.append(Point(id: nextPointID, down: down, up: up))
        nextPointID += 1
        if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }

        if let primaryInterface { localIP = snapshot[primaryInterface]?.ipv4 }
        if Date().timeIntervalSince(lastSave) >= 60 {
            store.save()
            lastSave = Date()
        }
    }

    /// Rebuilds the Settings interface list only when the set of interfaces actually changes.
    private func refreshInterfaceList(_ snapshot: [String: InterfaceSnapshot]) {
        let options = snapshot.values
            .filter { !$0.isLoopback }
            .map { InterfaceOption(name: $0.name, displayName: displayNames[$0.name] ?? $0.name, isActive: $0.isActive) }
            .sorted { ($0.isActive ? 0 : 1, $0.name) < ($1.isActive ? 0 : 1, $1.name) }
        if options != interfaces {
            if Set(options.map(\.name)) != Set(interfaces.map(\.name)) {
                displayNames = InterfaceReader.displayNames()
            }
            interfaces = options
        }
    }

    private func apply(_ path: NWPath) {
        isOnline = path.status == .satisfied
        guard isOnline, let primary = path.availableInterfaces.first else {
            primaryInterface = nil
            interfaceTitle = "No active connection"
            interfaceSymbol = "network.slash"
            localIP = nil
            return
        }
        primaryInterface = primary.name
        let kind: String
        switch primary.type {
        case .wifi: kind = "Wi-Fi"; interfaceSymbol = "wifi"
        case .wiredEthernet: kind = "Ethernet"; interfaceSymbol = "cable.connector"
        case .cellular: kind = "Cellular"; interfaceSymbol = "antenna.radiowaves.left.and.right"
        default: kind = "Network"; interfaceSymbol = "network"
        }
        let name = displayNames[primary.name] ?? kind
        interfaceTitle = "\(name) (\(primary.name))"
        localIP = InterfaceReader.snapshot()[primary.name]?.ipv4
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The first sample after wake would cover the whole sleep period and spike; skip it.
            Task { @MainActor in self?.discardNextSample = true }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.save() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.save() }
        })
    }
}
