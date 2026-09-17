import Foundation
import Model

/// 판정 규칙과 임계값 (F-32). 코드가 아니라 번들 `rules.json`에 있다.
///
/// 초기값은 요구사항 5장 표를 그대로 옮긴 것이다. 경계값이 들어가는지 빠지는지가 행마다 달라서
/// (`< 5%` 여유, `5~20%` 경계, `> 20%` 한계 / 메모리(강)은 `≥ 2%` 한계) 비교 연산자까지 JSON에 둔다.
///
/// `max_grade`는 12장 리스크 완화("초기에는 메모리만 한계 허용")를 옮긴 것이다.
public struct RuleSet: Sendable, Equatable, Decodable {
    public let schemaVersion: Int
    /// 판정에 필요한 최소 활성 시간 (F-34)
    public let minActiveHours: Double
    public let memory: ResourceRule
    /// "메모리(강)". 한계면 종합 판정이 한계다 (5장 보조 규칙)
    public let memoryCritical: ResourceRule
    public let cpu: ResourceRule
    public let gpu: ResourceRule
    public let thermal: ResourceRule
    public let disk: ResourceRule

    /// 앱에 번들된 규칙.
    public static func bundled() throws -> RuleSet {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> RuleSet {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RuleSet.self, from: data)
    }
}

/// 자원 하나의 한계 신호 정의와 등급 구간.
public struct ResourceRule: Sendable, Equatable, Decodable {
    /// 사람이 읽는 신호 정의. 판정에는 쓰지 않는다
    public let signal: String
    /// 이 자원이 받을 수 있는 가장 나쁜 등급
    public let maxGrade: Grade
    public let watch: Threshold
    public let limit: Threshold

    // 신호 매개변수. 자원마다 쓰는 것만 채운다
    public let swapUsedBytesAbove: UInt64?
    public let utilizationAtLeast: Double?
    public let sustainSeconds: Double?
    public let frequencyDropAtLeast: Double?
    public let singleEventMinutesAtLeast: Double?
    public let ioWaitAtLeast: Double?
    public let freeSpaceRatioBelow: Double?
}

/// 등급 경계 하나. 경계값을 포함하는지가 연산자로 정해진다.
public struct Threshold: Sendable, Equatable, Decodable {
    public enum Comparison: String, Sendable, Equatable, Decodable {
        case greaterThan = ">"
        case atLeast = ">="
    }

    public let op: Comparison
    public let value: Double

    public init(op: Comparison, value: Double) {
        self.op = op
        self.value = value
    }

    public func isMet(by measured: Double) -> Bool {
        switch op {
        case .greaterThan: measured > value
        case .atLeast: measured >= value
        }
    }
}
