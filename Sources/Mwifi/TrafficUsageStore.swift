import Foundation
import SQLite3

@MainActor
final class TrafficUsageStore: ObservableObject {
    struct PendingKey: Hashable {
        let dateKey: String
        let networkID: String
    }

    struct PendingValue {
        var networkName: String
        var networkKind: NetworkKind
        var uploaded: UInt64
        var downloaded: UInt64
    }

    @Published private(set) var revision = 0
    @Published private(set) var persistenceError: String?

    static let shared = TrafficUsageStore.makeDefault()
    static let flushInterval: Duration = .seconds(30)
    static let retentionMonths = 24

    private var database: OpaquePointer?
    private var pending: [PendingKey: PendingValue] = [:]
    private var lastFlushAttempt: ContinuousClock.Instant = .now
    private let isPersistent: Bool
    private let calendar: Calendar
    private var cachedTodayKey = ""
    private var cachedTodayTotals: TrafficTotals = .zero

    init(path: String, calendar: Calendar = .autoupdatingCurrent) throws {
        self.calendar = calendar
        self.isPersistent = path != ":memory:"
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw StoreError.openFailed
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA busy_timeout=250;")
        try execute("""
            CREATE TABLE IF NOT EXISTS daily_usage (
                date TEXT NOT NULL,
                network_id TEXT NOT NULL,
                network_name TEXT NOT NULL,
                network_kind TEXT NOT NULL,
                uploaded_bytes INTEGER NOT NULL DEFAULT 0,
                downloaded_bytes INTEGER NOT NULL DEFAULT 0,
                updated_at REAL NOT NULL,
                PRIMARY KEY (date, network_id)
            );
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_daily_usage_date ON daily_usage(date);")
        try execute("CREATE INDEX IF NOT EXISTS idx_daily_usage_network ON daily_usage(network_id);")
        try pruneOldRecords(referenceDate: Date())
        cachedTodayKey = dateKey(for: Date())
        cachedTodayTotals = queryTotals(dateKey: cachedTodayKey, networkID: nil)
    }

    deinit {
        sqlite3_close(database)
    }

    func record(
        delta: TrafficDelta,
        networkID: String,
        networkName: String,
        networkKind: NetworkKind,
        at date: Date = Date()
    ) {
        guard delta.uploaded > 0 || delta.downloaded > 0 else { return }
        let key = PendingKey(dateKey: dateKey(for: date), networkID: networkID)
        var value = pending[key] ?? PendingValue(
            networkName: networkName,
            networkKind: networkKind,
            uploaded: 0,
            downloaded: 0
        )
        value.networkName = networkName
        value.networkKind = networkKind
        value.uploaded &+= delta.uploaded
        value.downloaded &+= delta.downloaded
        pending[key] = value
        updateTodayCache(key: key, delta: delta)

        flushIfNeeded()
    }

    func flushIfNeeded() {
        guard !pending.isEmpty,
              lastFlushAttempt.duration(to: .now) >= Self.flushInterval else { return }
        flush()
    }

    func flush() {
        guard !pending.isEmpty else { return }
        lastFlushAttempt = .now
        let batch = pending
        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            for (key, value) in batch {
                try upsert(key: key, value: value)
            }
            try execute("COMMIT;")
            for key in batch.keys { pending.removeValue(forKey: key) }
            if isPersistent { persistenceError = nil }
            revision &+= 1
        } catch {
            try? execute("ROLLBACK;")
            persistenceError = "流量数据暂时无法保存，将自动重试。"
        }
    }

    func totals(for date: Date, networkID: String? = nil) -> TrafficTotals {
        let dateKey = dateKey(for: date)
        var totals = queryTotals(dateKey: dateKey, networkID: networkID)
        for (key, value) in pending where key.dateKey == dateKey && (networkID == nil || key.networkID == networkID) {
            totals = TrafficTotals(
                uploaded: totals.uploaded &+ value.uploaded,
                downloaded: totals.downloaded &+ value.downloaded
            )
        }
        return totals
    }

    func todayTotals(at date: Date = Date()) -> TrafficTotals {
        let key = dateKey(for: date)
        if key != cachedTodayKey {
            cachedTodayKey = key
            cachedTodayTotals = queryTotals(dateKey: key, networkID: nil)
            for (pendingKey, value) in pending where pendingKey.dateKey == key {
                cachedTodayTotals = TrafficTotals(
                    uploaded: cachedTodayTotals.uploaded &+ value.uploaded,
                    downloaded: cachedTodayTotals.downloaded &+ value.downloaded
                )
            }
        }
        return cachedTodayTotals
    }

    func dailyUsage(in month: Date, networkID: String? = nil) -> [DailyTrafficUsage] {
        flush()
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let startKey = dateKey(for: interval.start)
        let endKey = dateKey(for: interval.end)
        let sql: String
        if networkID == nil {
            sql = """
                SELECT date, '*', '所有网络', 'regularWiFi',
                       SUM(uploaded_bytes), SUM(downloaded_bytes)
                FROM daily_usage
                WHERE date >= ? AND date < ?
                GROUP BY date
                ORDER BY date;
                """
        } else {
            sql = """
                SELECT date, network_id, network_name, network_kind,
                       uploaded_bytes, downloaded_bytes
                FROM daily_usage
                WHERE date >= ? AND date < ? AND network_id = ?
                ORDER BY date;
                """
        }
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(startKey, at: 1, to: statement)
        bind(endKey, at: 2, to: statement)
        if let networkID { bind(networkID, at: 3, to: statement) }

        var results: [DailyTrafficUsage] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let dateString = columnText(statement, index: 0),
               let date = date(fromKey: dateString) {
                let kind = NetworkKind(rawValue: columnText(statement, index: 3) ?? "") ?? .regularWiFi
                results.append(DailyTrafficUsage(
                    date: date,
                    networkID: columnText(statement, index: 1) ?? "*",
                    networkName: columnText(statement, index: 2) ?? "未知 Wi-Fi",
                    networkKind: kind,
                    uploaded: UInt64(max(0, sqlite3_column_int64(statement, 4))),
                    downloaded: UInt64(max(0, sqlite3_column_int64(statement, 5)))
                ))
            }
            stepResult = sqlite3_step(statement)
        }
        if stepResult != SQLITE_DONE { reportReadFailure() }
        return results
    }

    func networks() -> [TrafficNetwork] {
        flush()
        let sql = """
            SELECT usage.network_id, usage.network_name, usage.network_kind
            FROM daily_usage AS usage
            WHERE usage.rowid = (
                SELECT candidate.rowid
                FROM daily_usage AS candidate
                WHERE candidate.network_id = usage.network_id
                ORDER BY candidate.updated_at DESC, candidate.date DESC
                LIMIT 1
            )
            ORDER BY usage.updated_at DESC;
            """
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [TrafficNetwork] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let id = columnText(statement, index: 0) ?? "未知 Wi-Fi"
            let name = columnText(statement, index: 1) ?? id
            let kind = NetworkKind(rawValue: columnText(statement, index: 2) ?? "") ?? .regularWiFi
            results.append(TrafficNetwork(id: id, name: name, kind: kind))
            stepResult = sqlite3_step(statement)
        }
        if stepResult != SQLITE_DONE { reportReadFailure() }
        return results
    }

    private static func makeDefault() -> TrafficUsageStore {
        do {
            let manager = FileManager.default
            let base = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("Mwifi", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try TrafficUsageStore(path: directory.appendingPathComponent("traffic.sqlite").path)
        } catch {
            let fallback = try! TrafficUsageStore(path: ":memory:")
            fallback.persistenceError = "流量数据库无法打开，本次运行的数据不会永久保存。"
            return fallback
        }
    }

    private func upsert(key: PendingKey, value: PendingValue) throws {
        let sql = """
            INSERT INTO daily_usage
                (date, network_id, network_name, network_kind, uploaded_bytes, downloaded_bytes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date, network_id) DO UPDATE SET
                network_name = excluded.network_name,
                network_kind = excluded.network_kind,
                uploaded_bytes = uploaded_bytes + excluded.uploaded_bytes,
                downloaded_bytes = downloaded_bytes + excluded.downloaded_bytes,
                updated_at = excluded.updated_at;
            """
        guard let statement = prepare(sql) else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }
        bind(key.dateKey, at: 1, to: statement)
        bind(key.networkID, at: 2, to: statement)
        bind(value.networkName, at: 3, to: statement)
        bind(value.networkKind.rawValue, at: 4, to: statement)
        sqlite3_bind_int64(statement, 5, Int64(clamping: value.uploaded))
        sqlite3_bind_int64(statement, 6, Int64(clamping: value.downloaded))
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.writeFailed }
    }

    private func updateTodayCache(key: PendingKey, delta: TrafficDelta) {
        let currentKey = dateKey(for: Date())
        guard key.dateKey == currentKey else { return }
        if cachedTodayKey != currentKey {
            cachedTodayKey = currentKey
            cachedTodayTotals = queryTotals(dateKey: currentKey, networkID: nil)
            for (pendingKey, value) in pending where pendingKey.dateKey == currentKey {
                cachedTodayTotals = TrafficTotals(
                    uploaded: cachedTodayTotals.uploaded &+ value.uploaded,
                    downloaded: cachedTodayTotals.downloaded &+ value.downloaded
                )
            }
            return
        }
        cachedTodayTotals = TrafficTotals(
            uploaded: cachedTodayTotals.uploaded &+ delta.uploaded,
            downloaded: cachedTodayTotals.downloaded &+ delta.downloaded
        )
    }

    private func queryTotals(dateKey: String, networkID: String?) -> TrafficTotals {
        let sql = networkID == nil
            ? "SELECT COALESCE(SUM(uploaded_bytes), 0), COALESCE(SUM(downloaded_bytes), 0) FROM daily_usage WHERE date = ?;"
            : "SELECT COALESCE(SUM(uploaded_bytes), 0), COALESCE(SUM(downloaded_bytes), 0) FROM daily_usage WHERE date = ? AND network_id = ?;"
        guard let statement = prepare(sql) else { return .zero }
        defer { sqlite3_finalize(statement) }
        bind(dateKey, at: 1, to: statement)
        if let networkID { bind(networkID, at: 2, to: statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            reportReadFailure()
            return .zero
        }
        return TrafficTotals(
            uploaded: UInt64(max(0, sqlite3_column_int64(statement, 0))),
            downloaded: UInt64(max(0, sqlite3_column_int64(statement, 1)))
        )
    }

    private func pruneOldRecords(referenceDate: Date) throws {
        guard let cutoff = calendar.date(byAdding: .month, value: -Self.retentionMonths, to: referenceDate) else { return }
        let cutoffKey = dateKey(for: cutoff)
        guard let statement = prepare("DELETE FROM daily_usage WHERE date < ?;") else { return }
        defer { sqlite3_finalize(statement) }
        bind(cutoffKey, at: 1, to: statement)
        _ = sqlite3_step(statement)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.executeFailed }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            reportReadFailure()
            return nil
        }
        return statement
    }

    private func reportReadFailure() {
        if isPersistent {
            persistenceError = "流量数据库读取失败，请重新打开 Mwifi 后再试。"
        }
    }

    private func bind(_ text: String, at index: Int32, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func date(fromKey key: String) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = values[0]
        components.month = values[1]
        components.day = values[2]
        return calendar.date(from: components)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum StoreError: Error {
    case openFailed
    case executeFailed
    case prepareFailed
    case writeFailed
}
