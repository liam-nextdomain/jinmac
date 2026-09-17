import Foundation

/// 판정 대상 자원 (요구사항 5장). "메모리(강)"은 별도 자원이 아니라 메모리의 두 번째 신호다.
public enum ResourceKind: String, Sendable, Hashable, Codable, CaseIterable {
    case memory
    case cpu
    case gpu
    case thermal
    case disk
}

/// 자원별 등급 (F-31). 선언 순서가 곧 심각도 순서다.
///
/// 원시값은 리포트 JSON에 그대로 남는다 (F-52). 바꾸면 이전 리포트와 비교가 깨진다.
public enum Grade: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    /// 여유
    case ample
    /// 경계
    case watch
    /// 한계
    case limit

    private var severity: Int {
        switch self {
        case .ample: 0
        case .watch: 1
        case .limit: 2
        }
    }

    public static func < (lhs: Grade, rhs: Grade) -> Bool {
        lhs.severity < rhs.severity
    }
}

/// 자원 하나에 대한 판정. 데이터가 모자라면 등급 대신 보류한다 (F-34).
public enum Judgement: Sendable, Hashable, Codable {
    case graded(Grade)
    case withheld(WithholdReason)
}

public enum WithholdReason: Sendable, Hashable, Codable {
    /// 유휴를 뺀 활성 시간이 기준에 못 미친다
    case insufficientActiveTime(hours: Double, required: Double)
    /// 이 기기에서 해당 지표를 읽을 수 없었다 (센서 결측)
    case metricUnavailable
}
