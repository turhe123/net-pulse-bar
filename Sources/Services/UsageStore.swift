import Foundation

/// Downloaded and uploaded byte totals for some period.
struct Usage: Codable, Equatable {
    var rx: UInt64 = 0
    var tx: UInt64 = 0

    mutating func add(rx: UInt64, tx: UInt64) {
        self.rx = self.rx &+ rx
        self.tx = self.tx &+ tx
    }
}

/// Persists per-day usage totals as JSON in Application Support and answers Today / Month / All Time queries.
@MainActor
final class UsageStore: ObservableObject {
    private struct FileContents: Codable {
        var days: [String: Usage]
        var allTime: Usage
    }

    static let retentionDays = 400

    @Published private(set) var days: [String: Usage] = [:]
    @Published private(set) var allTime = Usage()
    private var isDirty = false

    private let fileURL: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("NetPulseBar", isDirectory: true).appendingPathComponent("usage.json")
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        load()
        prune()
    }

    var today: Usage { days[Self.dayKey(Date())] ?? Usage() }

    var thisMonth: Usage {
        let month = String(Self.dayKey(Date()).prefix(7))
        return days.filter { $0.key.hasPrefix(month) }.values.reduce(into: Usage()) { $0.add(rx: $1.rx, tx: $1.tx) }
    }

    /// Adds bytes to today's entry; the key is computed per call so midnight rolls into a new day automatically.
    func add(rx: UInt64, tx: UInt64, at date: Date = Date()) {
        guard rx > 0 || tx > 0 else { return }
        days[Self.dayKey(date), default: Usage()].add(rx: rx, tx: tx)
        allTime.add(rx: rx, tx: tx)
        isDirty = true
    }

    /// Zeroes today's entry and the All Time counter while keeping older daily history.
    func resetCounters() {
        days[Self.dayKey(Date())] = Usage()
        allTime = Usage()
        isDirty = true
        save()
    }

    /// Deletes every stored total.
    func clearHistory() {
        days = [:]
        allTime = Usage()
        isDirty = true
        save()
    }

    func save() {
        guard isDirty, let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(FileContents(days: days, allTime: allTime))
            try data.write(to: url, options: .atomic)
            isDirty = false
        } catch {
            NSLog("NetPulseBar: failed to save usage: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        do {
            let contents = try JSONDecoder().decode(FileContents.self, from: data)
            days = contents.days
            allTime = contents.allTime
        } catch {
            NSLog("NetPulseBar: ignoring unreadable usage file: \(error.localizedDescription)")
        }
    }

    /// Drops entries older than the retention window. Keys are ISO dates, so string comparison orders them.
    private func prune() {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) else { return }
        let cutoff = Self.dayKey(cutoffDate)
        let before = days.count
        days = days.filter { $0.key >= cutoff }
        if days.count != before {
            isDirty = true
            save()
        }
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
}
