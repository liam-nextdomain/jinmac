import XCTest
@testable import Model

final class ModelTests: XCTestCase {

    func testGradeOrderIsSeverity() {
        XCTAssertLessThan(Grade.ample, .watch)
        XCTAssertLessThan(Grade.watch, .limit)
        XCTAssertEqual([Grade.limit, .ample, .watch].max(), .limit)
    }

    /// 읽지 못한 지표는 0이 아니라 nil이다 (요구사항 8장 견고성).
    func testNewSampleHasNoFabricatedReadings() {
        let sample = Sample(timestamp: 1_800_000_000)
        XCTAssertNil(sample.memoryPressure)
        XCTAssertNil(sample.cpuTotal)
        XCTAssertNil(sample.throttled)
        XCTAssertNil(sample.frontmostBundleID)
    }

    /// 7장 `mem_pressure` 컬럼 값.
    func testMemoryPressureRawValuesMatchSchema() {
        XCTAssertEqual(MemoryPressure.allCases.map(\.rawValue), [0, 1, 2])
    }
}
