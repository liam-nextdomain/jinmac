import XCTest
import Model
@testable import Verdict

/// 규칙 엔진 뼈대 (F-30~F-34). 번들 규칙이 요구사항 5장 표와 같은지, 경계값이 표대로 떨어지는지 본다.
final class VerdictTests: XCTestCase {

    private var rules: RuleSet!
    private var engine: RuleEngine!

    override func setUpWithError() throws {
        rules = try RuleSet.bundled()
        engine = RuleEngine(rules: rules)
    }

    func testBundledRulesMatchChapter5() {
        XCTAssertEqual(rules.schemaVersion, 1)
        XCTAssertEqual(rules.minActiveHours, 10)

        XCTAssertEqual(rules.memory.watch, Threshold(op: .atLeast, value: 0.05))
        XCTAssertEqual(rules.memory.limit, Threshold(op: .greaterThan, value: 0.20))
        XCTAssertEqual(rules.memory.swapUsedBytesAbove, 1 << 30)

        XCTAssertEqual(rules.memoryCritical.watch, Threshold(op: .greaterThan, value: 0))
        XCTAssertEqual(rules.memoryCritical.limit, Threshold(op: .atLeast, value: 0.02))

        XCTAssertEqual(rules.cpu.limit, Threshold(op: .greaterThan, value: 0.30))
        XCTAssertEqual(rules.gpu.limit, Threshold(op: .greaterThan, value: 0.30))
        XCTAssertEqual(rules.thermal.limit, Threshold(op: .atLeast, value: 4))
        XCTAssertEqual(rules.disk.limit, Threshold(op: .greaterThan, value: 0.15))
    }

    /// 12장 리스크 완화: 초기에는 메모리만 한계를 허용한다.
    func testOnlyMemoryMayReachLimitInitially() {
        XCTAssertEqual(rules.memory.maxGrade, .limit)
        XCTAssertEqual(rules.memoryCritical.maxGrade, .limit)
        for rule: ResourceRule in [rules.cpu, rules.gpu, rules.thermal, rules.disk] {
            XCTAssertEqual(rule.maxGrade, .watch)
        }
    }

    /// 5장 메모리 행: `< 5%` 여유, `5~20%` 경계, `> 20%` 한계.
    func testMemoryBoundaries() {
        let rule = rules.memory
        XCTAssertEqual(engine.judge(measured: 0.049, activeHours: 20, rule: rule), .graded(.ample))
        XCTAssertEqual(engine.judge(measured: 0.05, activeHours: 20, rule: rule), .graded(.watch))
        XCTAssertEqual(engine.judge(measured: 0.20, activeHours: 20, rule: rule), .graded(.watch))
        XCTAssertEqual(engine.judge(measured: 0.201, activeHours: 20, rule: rule), .graded(.limit))
    }

    /// 5장 메모리(강) 행: `0%` 여유, `< 2%` 경계, `≥ 2%` 한계.
    func testCriticalMemoryBoundaries() {
        let rule = rules.memoryCritical
        XCTAssertEqual(engine.judge(measured: 0, activeHours: 20, rule: rule), .graded(.ample))
        XCTAssertEqual(engine.judge(measured: 0.001, activeHours: 20, rule: rule), .graded(.watch))
        XCTAssertEqual(engine.judge(measured: 0.02, activeHours: 20, rule: rule), .graded(.limit))
    }

    func testGradeIsCappedByMaxGrade() {
        XCTAssertEqual(engine.judge(measured: 0.9, activeHours: 20, rule: rules.cpu), .graded(.watch))
    }

    /// F-34: 활성 시간 10시간 미만이면 등급 대신 보류.
    func testWithholdsBelowMinimumActiveTime() {
        XCTAssertEqual(
            engine.judge(measured: 0.9, activeHours: 9.5, rule: rules.memory),
            .withheld(.insufficientActiveTime(hours: 9.5, required: 10))
        )
    }
}
