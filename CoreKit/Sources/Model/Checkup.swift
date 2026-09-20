import Foundation

/// 검진 1회. 요구사항 7장 `checkup` 테이블의 한 행이다.
///
/// 시작·일시정지·재개·초기화의 전이 규칙(F-63)은 수집 루프가 가진다. 여기서는 저장되는 값의
/// 모양만 정한다.
public struct Checkup: Sendable, Hashable, Codable {
    public var id: Int64
    /// Unix 시각(초)
    public var startedAt: Int64
    /// 아직 끝나지 않은 검진은 `nil`
    public var endedAt: Int64?
    /// 사용자가 고른 검진 기간. 7·14·30일 중 하나이고 기본값은 14일이다 (F-01, 요구사항 14.1)
    public var targetDays: Int
    public var status: CheckupStatus

    public init(
        id: Int64,
        startedAt: Int64,
        endedAt: Int64? = nil,
        targetDays: Int,
        status: CheckupStatus
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetDays = targetDays
        self.status = status
    }
}

/// 검진 진행 상태 (F-63). 초기화는 행을 지우므로 상태가 따로 없다.
///
/// 원시값이 `checkup.status` 열에 그대로 남는다. 바꾸면 기존 데이터베이스를 읽지 못한다.
public enum CheckupStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// 수집 중
    case running
    /// 사용자가 일시정지했다
    case paused
    /// 목표 기간을 채우고 끝났다
    case completed
}

/// 저장된 리포트 한 행. 요구사항 7장 `report` 테이블이다.
///
/// `Store`는 `Report` 모듈을 import하지 않는다(모듈 의존 방향). 그래서 판정 결과와 문장을 이미
/// 직렬화된 JSON 문자열로 주고받고, 해석은 `Report` 쪽에서 한다.
public struct StoredReport: Sendable, Hashable, Codable {
    public var id: Int64
    public var checkupID: Int64
    public var createdAt: Int64
    /// 판정 결과. 규칙 엔진의 산출물이고 AI가 건드리지 않는다 (A-02)
    public var verdictJSON: String
    /// 리포트 문장. 아직 생성하지 않았으면 `nil`
    public var textJSON: String?
    /// 비교 기능이 호환성을 먼저 검사한다 (F-52)
    public var schemaVersion: Int

    public init(
        id: Int64,
        checkupID: Int64,
        createdAt: Int64,
        verdictJSON: String,
        textJSON: String? = nil,
        schemaVersion: Int
    ) {
        self.id = id
        self.checkupID = checkupID
        self.createdAt = createdAt
        self.verdictJSON = verdictJSON
        self.textJSON = textJSON
        self.schemaVersion = schemaVersion
    }
}
