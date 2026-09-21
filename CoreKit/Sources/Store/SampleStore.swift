import Foundation
import Model
import SQLite3

/// 검진 데이터 저장소. 요구사항 7장의 SQLite 파일 하나를 연다.
///
/// GRDB가 아니라 시스템 SQLite3를 직접 쓴다 (요구사항 14.1). 연결 하나를 이 actor가 소유하고,
/// 모든 접근은 actor를 거친다.
///
/// 스키마 v1은 1단계에 필요한 `sample`·`checkup`·`report` 세 테이블이다. `top_process`,
/// `session`, `session_sample`, `app_category`는 2단계에서 더한다. `sample`은 7장의 열을 처음부터
/// 다 만들어 두고, 아직 수집하지 않는 지표는 NULL로 남긴다. 그래야 2단계에서 수집 항목이 늘어도
/// 마이그레이션이 필요 없다.
public actor SampleStore {

    /// 현재 스키마 버전. 테이블이 바뀔 때마다 `migrations`에 한 단계를 더하고 이 값을 올린다.
    public static let schemaVersion: Int32 = 1

    public static let fileName = "jinmac.sqlite"

    private let connection: Connection
    private var db: OpaquePointer { connection.handle }

    /// 기본 저장 경로 `~/Library/Application Support/JinMac/`.
    ///
    /// 테스트와 검증 스크립트는 `JINMAC_DATA_DIR`로 경로를 바꿔 사용자의 검진 데이터를 건드리지
    /// 않는다.
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["JINMAC_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("JinMac", isDirectory: true)
    }

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(Self.fileName).path

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw StoreError.open(code: rc)
        }
        connection = Connection(handle: handle)

        try Self.execute(handle, "PRAGMA journal_mode=WAL")
        // 연결마다 켜야 한다. 꺼져 있으면 `report.checkup_id`가 없는 검진을 가리켜도 통과한다.
        try Self.execute(handle, "PRAGMA foreign_keys=ON")
        try Self.migrate(handle)
    }

    // MARK: - 스키마

    /// 배열의 `i`번째가 버전 `i+1`로 올리는 단계다. 이미 나간 단계는 절대 고치지 않고 뒤에 더한다.
    private static let migrations: [String] = [
        """
        CREATE TABLE sample (
            ts              INTEGER PRIMARY KEY,
            mem_used        INTEGER,
            mem_compressed  INTEGER,
            swap_used       INTEGER,
            swap_in         INTEGER,
            swap_out        INTEGER,
            mem_pressure    INTEGER,
            cpu_total       REAL,
            cpu_p           REAL,
            cpu_e           REAL,
            cpu_freq        REAL,
            gpu_util        REAL,
            gpu_mem         INTEGER,
            disk_read       INTEGER,
            disk_write      INTEGER,
            io_wait         REAL,
            disk_free_ratio REAL,
            temp_cpu        REAL,
            temp_gpu        REAL,
            fan_rpm         REAL,
            throttled       INTEGER,
            on_battery      INTEGER,
            idle            INTEGER,
            front_app       TEXT
        );

        CREATE TABLE checkup (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at  INTEGER NOT NULL,
            ended_at    INTEGER,
            target_days INTEGER NOT NULL,
            status      TEXT    NOT NULL
        );

        CREATE TABLE report (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            checkup_id     INTEGER NOT NULL REFERENCES checkup(id) ON DELETE CASCADE,
            created_at     INTEGER NOT NULL,
            verdict_json   TEXT    NOT NULL,
            text_json      TEXT,
            schema_version INTEGER NOT NULL
        );

        CREATE INDEX report_by_checkup ON report(checkup_id);
        """,
    ]

    /// `ts`는 rowid 별칭이라 따로 색인하지 않아도 기간 조회가 색인을 탄다.
    private static let sampleColumns = [
        "ts",
        "mem_used", "mem_compressed", "swap_used", "swap_in", "swap_out", "mem_pressure",
        "cpu_total", "cpu_p", "cpu_e", "cpu_freq",
        "gpu_util", "gpu_mem",
        "disk_read", "disk_write", "io_wait", "disk_free_ratio",
        "temp_cpu", "temp_gpu", "fan_rpm", "throttled",
        "on_battery", "idle", "front_app",
    ]

    private static func migrate(_ db: OpaquePointer) throws {
        let current = try queryInt(db, "PRAGMA user_version")
        guard current < Int32(migrations.count) else { return }

        for step in Int(current)..<migrations.count {
            try execute(db, "BEGIN")
            do {
                try execute(db, migrations[step])
                // PRAGMA는 바인딩을 받지 못해 문자열로 넣는다. 값은 배열 길이라 외부 입력이 아니다.
                try execute(db, "PRAGMA user_version=\(step + 1)")
                try execute(db, "COMMIT")
            } catch {
                try? execute(db, "ROLLBACK")
                throw error
            }
        }
    }

    public func userVersion() throws -> Int32 {
        try Self.queryInt(db, "PRAGMA user_version")
    }

    public func journalMode() throws -> String {
        try Self.queryText(db, "PRAGMA journal_mode")
    }

    /// 만들어진 테이블 이름. 마이그레이션 확인용이다.
    public func tableNames() throws -> [String] {
        let statement = try SQLiteStatement(
            db: db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """)
        var names: [String] = []
        while try statement.step() {
            if let name = statement.text(0) { names.append(name) }
        }
        return names
    }

    // MARK: - 샘플

    /// 배치를 트랜잭션 하나로 넣는다. 행마다 커밋하면 하루 디스크 쓰기 5MB 예산을 넘긴다
    /// (요구사항 8장, 14.5b).
    ///
    /// 같은 `ts`가 다시 오면 나중 값으로 덮는다. 잠자기나 시계 보정으로 같은 초가 두 번 나올 수
    /// 있는데, 거기서 배치 전체를 버리면 수집이 멈춘다 (요구사항 8장).
    public func insert(_ samples: [Sample]) throws {
        guard !samples.isEmpty else { return }

        let placeholders = Array(repeating: "?", count: Self.sampleColumns.count).joined(separator: ", ")
        let statement = try SQLiteStatement(
            db: db,
            sql: """
                INSERT OR REPLACE INTO sample (\(Self.sampleColumns.joined(separator: ", ")))
                VALUES (\(placeholders))
                """)

        try Self.execute(db, "BEGIN")
        do {
            for sample in samples {
                statement.reset()
                Self.bind(sample, to: statement)
                try statement.run()
            }
            try Self.execute(db, "COMMIT")
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }
    }

    public func sampleCount() throws -> Int {
        Int(try Self.queryInt(db, "SELECT COUNT(*) FROM sample"))
    }

    /// 기간 안의 샘플을 행 단위로 누적한다. 14일치는 약 24만 행이라 배열로 올리지 않는다.
    ///
    /// 양 끝을 포함하고 `ts` 오름차순으로 돈다. 판정은 시간 순서를 가정한다.
    public func reduceSamples<T: Sendable>(
        from start: Int64,
        to end: Int64,
        into initial: T,
        _ accumulate: @Sendable (inout T, Sample) -> Void
    ) throws -> T {
        let statement = try Self.selectSamples(db, from: start, to: end, limit: nil)
        var value = initial
        while try statement.step() {
            accumulate(&value, Self.readSample(from: statement))
        }
        return value
    }

    /// 짧은 구간을 배열로 받는다. `limit`을 필수로 둬서 24만 행을 실수로 올리지 못하게 한다.
    /// 긴 구간은 `reduceSamples`를 쓴다.
    public func samples(from start: Int64, to end: Int64, limit: Int) throws -> [Sample] {
        let statement = try Self.selectSamples(db, from: start, to: end, limit: limit)
        var rows: [Sample] = []
        while try statement.step() {
            rows.append(Self.readSample(from: statement))
        }
        return rows
    }

    private static func selectSamples(
        _ db: OpaquePointer,
        from start: Int64,
        to end: Int64,
        limit: Int?
    ) throws -> SQLiteStatement {
        var sql = """
            SELECT \(sampleColumns.joined(separator: ", ")) FROM sample
            WHERE ts BETWEEN ? AND ?
            ORDER BY ts
            """
        if limit != nil { sql += "\nLIMIT ?" }

        let statement = try SQLiteStatement(db: db, sql: sql)
        statement.bind(1, start)
        statement.bind(2, end)
        if let limit { statement.bind(3, limit) }
        return statement
    }

    private static func bind(_ sample: Sample, to statement: SQLiteStatement) {
        statement.bind(1, sample.timestamp)
        statement.bind(2, sample.memoryUsedBytes)
        statement.bind(3, sample.memoryCompressedBytes)
        statement.bind(4, sample.swapUsedBytes)
        statement.bind(5, sample.swapInBytes)
        statement.bind(6, sample.swapOutBytes)
        statement.bind(7, sample.memoryPressure?.rawValue)
        statement.bind(8, sample.cpuTotal)
        statement.bind(9, sample.cpuPerformance)
        statement.bind(10, sample.cpuEfficiency)
        statement.bind(11, sample.cpuFrequencyMHz)
        statement.bind(12, sample.gpuUtilization)
        statement.bind(13, sample.gpuMemoryBytes)
        statement.bind(14, sample.diskReadBytes)
        statement.bind(15, sample.diskWriteBytes)
        statement.bind(16, sample.ioWait)
        statement.bind(17, sample.diskFreeRatio)
        statement.bind(18, sample.cpuTemperature)
        statement.bind(19, sample.gpuTemperature)
        statement.bind(20, sample.fanRPM)
        statement.bind(21, sample.throttled)
        statement.bind(22, sample.onBattery)
        statement.bind(23, sample.idle)
        statement.bind(24, sample.frontmostBundleID)
    }

    private static func readSample(from statement: SQLiteStatement) -> Sample {
        var sample = Sample(timestamp: statement.int64(0) ?? 0)
        sample.memoryUsedBytes = statement.uint64(1)
        sample.memoryCompressedBytes = statement.uint64(2)
        sample.swapUsedBytes = statement.uint64(3)
        sample.swapInBytes = statement.uint64(4)
        sample.swapOutBytes = statement.uint64(5)
        sample.memoryPressure = statement.int(6).flatMap(MemoryPressure.init(rawValue:))
        sample.cpuTotal = statement.double(7)
        sample.cpuPerformance = statement.double(8)
        sample.cpuEfficiency = statement.double(9)
        sample.cpuFrequencyMHz = statement.double(10)
        sample.gpuUtilization = statement.double(11)
        sample.gpuMemoryBytes = statement.uint64(12)
        sample.diskReadBytes = statement.uint64(13)
        sample.diskWriteBytes = statement.uint64(14)
        sample.ioWait = statement.double(15)
        sample.diskFreeRatio = statement.double(16)
        sample.cpuTemperature = statement.double(17)
        sample.gpuTemperature = statement.double(18)
        sample.fanRPM = statement.double(19)
        sample.throttled = statement.bool(20)
        sample.onBattery = statement.bool(21)
        sample.idle = statement.bool(22)
        sample.frontmostBundleID = statement.text(23)
        return sample
    }

    // MARK: - 검진

    /// 새 검진을 시작하고 그 `id`를 돌려준다. 상태 전이 규칙은 수집 루프가 가진다 (F-63).
    @discardableResult
    public func insertCheckup(startedAt: Int64, targetDays: Int) throws -> Int64 {
        let statement = try SQLiteStatement(
            db: db,
            sql: "INSERT INTO checkup (started_at, ended_at, target_days, status) VALUES (?, NULL, ?, ?)")
        statement.bind(1, startedAt)
        statement.bind(2, targetDays)
        statement.bind(3, CheckupStatus.running.rawValue)
        try statement.run()
        return sqlite3_last_insert_rowid(db)
    }

    public func updateCheckup(id: Int64, status: CheckupStatus, endedAt: Int64? = nil) throws {
        let statement = try SQLiteStatement(
            db: db,
            sql: "UPDATE checkup SET status = ?, ended_at = ? WHERE id = ?")
        statement.bind(1, status.rawValue)
        statement.bind(2, endedAt)
        statement.bind(3, id)
        try statement.run()
    }

    public func checkup(id: Int64) throws -> Checkup? {
        let statement = try SQLiteStatement(
            db: db,
            sql: "SELECT id, started_at, ended_at, target_days, status FROM checkup WHERE id = ?")
        statement.bind(1, id)
        guard try statement.step() else { return nil }
        return Self.readCheckup(from: statement)
    }

    /// 시작이 늦은 것부터. 과거 리포트 목록이 이 순서를 쓴다 (F-44).
    public func checkups() throws -> [Checkup] {
        let statement = try SQLiteStatement(
            db: db,
            sql: """
                SELECT id, started_at, ended_at, target_days, status FROM checkup
                ORDER BY started_at DESC
                """)
        var rows: [Checkup] = []
        while try statement.step() {
            rows.append(Self.readCheckup(from: statement))
        }
        return rows
    }

    private static func readCheckup(from statement: SQLiteStatement) -> Checkup {
        Checkup(
            id: statement.int64(0) ?? 0,
            startedAt: statement.int64(1) ?? 0,
            endedAt: statement.int64(2),
            targetDays: statement.int(3) ?? 0,
            status: statement.text(4).flatMap(CheckupStatus.init(rawValue:)) ?? .paused)
    }

    // MARK: - 리포트

    /// 판정 결과와 문장을 나누어 저장한다 (7장). `Store`는 두 JSON의 내용을 해석하지 않는다.
    @discardableResult
    public func insertReport(
        checkupID: Int64,
        createdAt: Int64,
        verdictJSON: String,
        textJSON: String?,
        schemaVersion: Int
    ) throws -> Int64 {
        let statement = try SQLiteStatement(
            db: db,
            sql: """
                INSERT INTO report (checkup_id, created_at, verdict_json, text_json, schema_version)
                VALUES (?, ?, ?, ?, ?)
                """)
        statement.bind(1, checkupID)
        statement.bind(2, createdAt)
        statement.bind(3, verdictJSON)
        statement.bind(4, textJSON)
        statement.bind(5, schemaVersion)
        try statement.run()
        return sqlite3_last_insert_rowid(db)
    }

    public func report(id: Int64) throws -> StoredReport? {
        let statement = try SQLiteStatement(
            db: db,
            sql: """
                SELECT id, checkup_id, created_at, verdict_json, text_json, schema_version
                FROM report WHERE id = ?
                """)
        statement.bind(1, id)
        guard try statement.step() else { return nil }
        return StoredReport(
            id: statement.int64(0) ?? 0,
            checkupID: statement.int64(1) ?? 0,
            createdAt: statement.int64(2) ?? 0,
            verdictJSON: statement.text(3) ?? "",
            textJSON: statement.text(4),
            schemaVersion: statement.int(5) ?? 0)
    }

    // MARK: - SQLite3 호출

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard rc == SQLITE_OK else {
            throw StoreError.statement(code: rc, message: message.map { String(cString: $0) } ?? "")
        }
    }

    private static func withRow<T>(_ db: OpaquePointer, _ sql: String, _ read: (OpaquePointer) -> T) throws -> T {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw StoreError.statement(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let step = sqlite3_step(stmt)
        guard step == SQLITE_ROW else {
            throw StoreError.statement(code: step, message: String(cString: sqlite3_errmsg(db)))
        }
        return read(stmt)
    }

    private static func queryInt(_ db: OpaquePointer, _ sql: String) throws -> Int32 {
        try withRow(db, sql) { sqlite3_column_int($0, 0) }
    }

    private static func queryText(_ db: OpaquePointer, _ sql: String) throws -> String {
        try withRow(db, sql) { stmt in
            sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        }
    }
}

/// 연결 핸들의 수명. actor의 `deinit`은 non-Sendable 핸들에 접근할 수 없어 닫기를 여기서 맡는다.
private final class Connection {
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

public enum StoreError: Error, Equatable {
    case open(code: Int32)
    case statement(code: Int32, message: String)
}
