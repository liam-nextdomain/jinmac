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

    /// 검진 기간은 7·14·30일 중 하나이고 기본값은 14일이다 (F-01, 요구사항 14.1).
    func testTargetDayChoicesFollowF01() {
        XCTAssertEqual(Checkup.targetDayChoices, [7, 14, 30])
        XCTAssertEqual(Checkup.defaultTargetDays, 14)
    }

    /// 예정 종료 시각은 시작 시각에 목표 일수를 더한 벽시계 시각이다. 일시정지한 구간도 포함한다.
    func testScheduledEndIsStartPlusTargetDays() {
        let checkup = Checkup(id: 1, startedAt: 1_758_500_000, targetDays: 7, status: .paused)
        XCTAssertEqual(checkup.scheduledEndAt, 1_758_500_000 + 7 * 86_400)
    }

    func testOnlyRunningAndPausedAreInProgress() {
        XCTAssertTrue(CheckupStatus.running.isInProgress)
        XCTAssertTrue(CheckupStatus.paused.isInProgress)
        XCTAssertFalse(CheckupStatus.completed.isInProgress)
    }
}
