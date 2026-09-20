import Foundation
import SQLite3

/// 준비된 구문 하나의 수명. `deinit`에서 `sqlite3_finalize`를 부른다.
///
/// non-Sendable 핸들을 들고 있으므로 `SampleStore` actor 안에서만 만들고 쓴다. 밖으로 넘기지
/// 않는다 (`.claude/rules/corekit.md`).
final class SQLiteStatement {
    private let handle: OpaquePointer
    private let db: OpaquePointer

    /// SQLite가 문자열을 자기 버퍼로 복사하게 한다. Swift의 `String`은 호출이 끝나면 포인터를
    /// 보장하지 않으므로 `SQLITE_STATIC`을 쓰면 안 된다.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    init(db: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw StoreError.statement(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
        self.handle = statement
        self.db = db
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: - 실행

    /// 다음 행이 있으면 `true`.
    @discardableResult
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.statement(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 행을 돌려주지 않는 구문을 끝까지 실행한다.
    func run() throws {
        while try step() {}
    }

    /// 배치 삽입은 구문 하나를 재사용한다. 행마다 새로 준비하면 5초 간격의 예산을 넘긴다.
    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    // MARK: - 바인딩

    /// 결측은 0이 아니라 NULL이다. 0으로 넣으면 규칙 엔진이 "여유"로 읽는다.
    func bind(_ index: Int32, _ value: Int64?) {
        if let value {
            sqlite3_bind_int64(handle, index, value)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    /// 바이트 수는 `Int64.max`를 넘을 수 있다. 비트 패턴 그대로 넣고 그대로 읽어 값을 보존한다.
    func bind(_ index: Int32, _ value: UInt64?) {
        bind(index, value.map { Int64(bitPattern: $0) })
    }

    func bind(_ index: Int32, _ value: Int?) {
        bind(index, value.map(Int64.init))
    }

    func bind(_ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(handle, index, value)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    func bind(_ index: Int32, _ value: Bool?) {
        bind(index, value.map { Int64($0 ? 1 : 0) })
    }

    func bind(_ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(handle, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    // MARK: - 읽기

    private func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    func int64(_ index: Int32) -> Int64? {
        isNull(index) ? nil : sqlite3_column_int64(handle, index)
    }

    func uint64(_ index: Int32) -> UInt64? {
        int64(index).map { UInt64(bitPattern: $0) }
    }

    func int(_ index: Int32) -> Int? {
        int64(index).map(Int.init)
    }

    func double(_ index: Int32) -> Double? {
        isNull(index) ? nil : sqlite3_column_double(handle, index)
    }

    func bool(_ index: Int32) -> Bool? {
        int64(index).map { $0 != 0 }
    }

    func text(_ index: Int32) -> String? {
        guard !isNull(index), let raw = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: raw)
    }
}
