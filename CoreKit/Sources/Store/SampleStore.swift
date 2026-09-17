import Foundation
import SQLite3

/// 검진 데이터 저장소. 요구사항 7장의 SQLite 파일 하나를 연다.
///
/// GRDB가 아니라 시스템 SQLite3를 직접 쓴다 (요구사항 14.1). 연결 하나를 이 actor가 소유하고,
/// 모든 접근은 actor를 거친다.
///
/// 7장의 테이블은 아직 만들지 않는다. `user_version`이 스키마 버전이고, 테이블을 추가할 때마다
/// 올린다.
public actor SampleStore {

    /// 현재 스키마 버전. 0 = 테이블 없음
    public static let schemaVersion: Int32 = 0

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
    }

    public func userVersion() throws -> Int32 {
        try Self.queryInt(db, "PRAGMA user_version")
    }

    public func journalMode() throws -> String {
        try Self.queryText(db, "PRAGMA journal_mode")
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
