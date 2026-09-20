import XCTest
@testable import Model
@testable import Store

/// 임시 디렉터리에서만 연다. 사용자의 `~/Library/Application Support/JinMac/`은 건드리지 않는다.
final class StoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinMacStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func openStore() throws -> SampleStore {
        try SampleStore(directory: directory)
    }

    // MARK: - 열기와 마이그레이션

    func testOpensInWALModeAtCurrentSchemaVersion() async throws {
        let store = try openStore()
        let mode = try await store.journalMode()
        let version = try await store.userVersion()
        XCTAssertEqual(mode, "wal")
        XCTAssertEqual(version, SampleStore.schemaVersion)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(SampleStore.fileName).path))
    }

    func testDataDirectoryOverride() {
        let url = SampleStore.defaultDirectory(environment: ["JINMAC_DATA_DIR": "/tmp/jinmac-test"])
        XCTAssertEqual(url.path, "/tmp/jinmac-test")
    }

    func testDefaultDirectoryIsApplicationSupport() {
        let url = SampleStore.defaultDirectory(environment: [:])
        XCTAssertEqual(url.lastPathComponent, "JinMac")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    /// 7장의 1단계 테이블 세 개가 스키마 v1에 있다. 2단계 테이블은 아직 만들지 않는다.
    func testCreatesStageOneTables() async throws {
        let store = try openStore()
        let tables = try await store.tableNames()
        XCTAssertEqual(tables, ["checkup", "report", "sample"])
        XCTAssertEqual(SampleStore.schemaVersion, 1)
    }

    /// 두 번째로 열 때 DDL을 다시 돌리지 않는다. 돌리면 `table already exists`로 실패한다.
    func testMigrationIsIdempotent() async throws {
        let first = try openStore()
        _ = try await first.userVersion()
        let second = try openStore()
        let version = try await second.userVersion()
        let tables = try await second.tableNames()
        XCTAssertEqual(version, SampleStore.schemaVersion)
        XCTAssertEqual(tables, ["checkup", "report", "sample"])
    }

    // MARK: - 샘플 저장

    /// 7장 `sample`의 모든 열이 값을 잃지 않고 돌아온다.
    func testRoundTripsEverySampleColumn() async throws {
        let store = try openStore()
        let written = Self.fullSample(timestamp: 1_758_300_000)
        try await store.insert([written])

        let read = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(read, [written])
    }

    /// 읽지 못한 지표는 0이 아니라 NULL로 남고, `nil`로 돌아온다. 0으로 돌아오면
    /// 규칙 엔진이 "여유"로 읽는다.
    func testMissingReadingsStayNilAndNeverBecomeZero() async throws {
        let store = try openStore()
        let sparse = Sample(timestamp: 1_758_300_005)
        try await store.insert([sparse])

        let read = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(read, [sparse])
        XCTAssertNil(read.first?.memoryUsedBytes)
        XCTAssertNil(read.first?.cpuTotal)
        XCTAssertNil(read.first?.throttled)
        XCTAssertNil(read.first?.frontmostBundleID)
    }

    /// 바이트 수는 `UInt64`이고 `Int64`의 최댓값을 넘을 수 있다. 값이 깨지면 안 된다.
    func testStoresByteCountsBeyondInt64Max() async throws {
        let store = try openStore()
        var sample = Sample(timestamp: 1_758_300_010)
        sample.swapOuts = UInt64.max
        try await store.insert([sample])

        let read = try await store.samples(from: 0, to: .max, limit: 1)
        XCTAssertEqual(read.first?.swapOuts, UInt64.max)
    }

    func testInsertsBatchInOneTransaction() async throws {
        let store = try openStore()
        let batch = (0..<500).map { Sample(timestamp: 1_758_300_000 + Int64($0) * 5) }
        try await store.insert(batch)
        let count = try await store.sampleCount()
        XCTAssertEqual(count, 500)
    }

    /// 잠자기나 시계 보정으로 같은 초가 두 번 나와도 수집이 멈추면 안 된다 (요구사항 8장).
    /// 같은 `ts`는 나중 값으로 덮고, 배치 전체를 버리지 않는다.
    func testRepeatedTimestampReplacesInsteadOfFailing() async throws {
        let store = try openStore()
        var first = Sample(timestamp: 1_758_300_000)
        first.cpuTotal = 0.10
        var second = Sample(timestamp: 1_758_300_000)
        second.cpuTotal = 0.90

        try await store.insert([first, Sample(timestamp: 1_758_300_005)])
        try await store.insert([second])

        let read = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read.first?.cpuTotal, 0.90)
    }

    // MARK: - 기간 조회

    func testPeriodQueryIncludesBothBoundsInTimestampOrder() async throws {
        let store = try openStore()
        let stamps: [Int64] = [300, 100, 500, 200, 400]
        try await store.insert(stamps.map { Sample(timestamp: $0) })

        let read = try await store.samples(from: 200, to: 400, limit: 100)
        XCTAssertEqual(read.map(\.timestamp), [200, 300, 400])
    }

    /// 14일치는 약 24만 행이다. 배열로 올리지 않고 행 단위로 누적한다.
    func testReducesRowByRowWithoutMaterialising() async throws {
        let store = try openStore()
        try await store.insert((0..<1_000).map { index -> Sample in
            var sample = Sample(timestamp: Int64(index))
            sample.cpuTotal = 0.5
            return sample
        })

        let total = try await store.reduceSamples(from: 0, to: .max, into: 0.0) { sum, sample in
            sum += sample.cpuTotal ?? 0
        }
        XCTAssertEqual(total, 500.0, accuracy: 0.0001)
    }

    // MARK: - 검진과 리포트

    func testInsertsAndUpdatesCheckup() async throws {
        let store = try openStore()
        let id = try await store.insertCheckup(startedAt: 1_758_300_000, targetDays: 14)

        var checkup = try await store.checkup(id: id)
        XCTAssertEqual(checkup?.status, .running)
        XCTAssertEqual(checkup?.targetDays, 14)
        XCTAssertNil(checkup?.endedAt)

        try await store.updateCheckup(id: id, status: .completed, endedAt: 1_759_500_000)
        checkup = try await store.checkup(id: id)
        XCTAssertEqual(checkup?.status, .completed)
        XCTAssertEqual(checkup?.endedAt, 1_759_500_000)
    }

    func testStoresReportAgainstCheckup() async throws {
        let store = try openStore()
        let checkupID = try await store.insertCheckup(startedAt: 1_758_300_000, targetDays: 7)
        let id = try await store.insertReport(
            checkupID: checkupID,
            createdAt: 1_758_904_800,
            verdictJSON: #"{"memory":"limit"}"#,
            textJSON: nil,
            schemaVersion: 1)

        let report = try await store.report(id: id)
        XCTAssertEqual(report?.checkupID, checkupID)
        XCTAssertEqual(report?.verdictJSON, #"{"memory":"limit"}"#)
        XCTAssertEqual(report?.schemaVersion, 1)
        XCTAssertNil(report?.textJSON, "문장 생성 전이면 비어 있다")
    }

    /// 없는 검진에 리포트를 붙일 수 없다. 외래 키가 꺼져 있으면 이 테스트가 통과해 버린다.
    func testRejectsReportForUnknownCheckup() async throws {
        let store = try openStore()
        await XCTAssertThrowsErrorAsync(try await store.insertReport(
            checkupID: 404,
            createdAt: 1_758_904_800,
            verdictJSON: "{}",
            textJSON: nil,
            schemaVersion: 1))
    }

    // MARK: - 픽스처

    /// 모든 열에 서로 다른 값을 넣어, 바인딩 순서가 어긋나면 반드시 실패하게 한다.
    private static func fullSample(timestamp: Int64) -> Sample {
        var sample = Sample(timestamp: timestamp)
        sample.memoryUsedBytes = 21_474_836_480
        sample.memoryCompressedBytes = 3_221_225_472
        sample.swapUsedBytes = 1_073_741_824
        sample.swapIns = 12_345
        sample.swapOuts = 67_890
        sample.memoryPressure = .warning
        sample.cpuTotal = 0.41
        sample.cpuPerformance = 0.62
        sample.cpuEfficiency = 0.23
        sample.cpuFrequencyMHz = 3_780
        sample.gpuUtilization = 0.17
        sample.gpuMemoryBytes = 2_147_483_648
        sample.diskReadBytes = 98_765
        sample.diskWriteBytes = 43_210
        sample.ioWait = 0.07
        sample.diskFreeRatio = 0.35
        sample.cpuTemperature = 61.5
        sample.gpuTemperature = 57.25
        sample.fanRPM = 1_842
        sample.throttled = false
        sample.onBattery = true
        sample.idle = false
        sample.frontmostBundleID = "com.apple.dt.Xcode"
        return sample
    }
}

/// `XCTAssertThrowsError`는 `async` 식을 받지 못한다.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("오류가 나야 한다", file: file, line: line)
    } catch {}
}
