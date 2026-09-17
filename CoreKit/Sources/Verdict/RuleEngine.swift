import Model

/// 규칙 엔진 (F-30~F-34).
///
/// 같은 입력에는 항상 같은 출력을 낸다 (F-33). 그래서 이 모듈에서는 다음을 쓰지 않는다.
/// - `Date()`, 난수: 시각은 입력으로 받는다
/// - `Dictionary`·`Set` 순회: 순서가 프로세스마다 달라진다. 정렬한 뒤 순회한다
/// - IOKit·AppKit·`Collector`·`Store`: 판정은 저장된 값만 본다
public struct RuleEngine: Sendable {
    public let rules: RuleSet

    public init(rules: RuleSet) {
        self.rules = rules
    }

    /// 한계 신호가 활성 시간 중 차지한 비율(또는 활성 주당 횟수)을 등급으로 바꾼다.
    ///
    /// 결과는 규칙의 `max_grade`를 넘지 않는다. 활성 시간이 모자라면 보류한다 (F-34).
    public func judge(measured: Double, activeHours: Double, rule: ResourceRule) -> Judgement {
        guard activeHours >= rules.minActiveHours else {
            return .withheld(.insufficientActiveTime(hours: activeHours, required: rules.minActiveHours))
        }
        let raw: Grade
        if rule.limit.isMet(by: measured) {
            raw = .limit
        } else if rule.watch.isMet(by: measured) {
            raw = .watch
        } else {
            raw = .ample
        }
        return .graded(min(raw, rule.maxGrade))
    }
}
