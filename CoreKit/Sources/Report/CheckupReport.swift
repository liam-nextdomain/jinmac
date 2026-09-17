import Foundation
import Model

/// 검진 리포트 (F-40). 판정 결과와 문장을 분리해 저장한다 (7장 `report`의 `verdict_json`·`text_json`).
///
/// JSON으로 내보내고 다른 기기의 리포트와 나란히 비교한다 (F-52). `schemaVersion`이 다르면
/// 비교 화면이 호환성을 먼저 검사한다.
public struct CheckupReport: Sendable, Equatable, Codable {
    /// 필드를 바꾸면 올린다
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var device: DeviceInfo
    public var findings: [ResourceFinding]

    public init(device: DeviceInfo, findings: [ResourceFinding]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.device = device
        self.findings = findings
    }

    /// 같은 리포트는 항상 같은 바이트가 된다. 키를 정렬하지 않으면 비교와 이슈 첨부가 흔들린다.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// 리포트 카드에 들어가는 기기 정보 (F-50). 사용자 이름·일련번호는 넣지 않는다.
public struct DeviceInfo: Sendable, Equatable, Codable {
    /// `sysctl hw.model`, 예: `Mac17,2`
    public var model: String
    /// `sysctl machdep.cpu.brand_string`, 예: `Apple M5`
    public var chip: String
    public var memoryBytes: UInt64

    public init(model: String, chip: String, memoryBytes: UInt64) {
        self.model = model
        self.chip = chip
        self.memoryBytes = memoryBytes
    }
}

/// 자원 하나의 판정과 근거 (F-31). 근거 없는 권고는 출력하지 않는다 (2장).
public struct ResourceFinding: Sendable, Equatable, Codable {
    public var resource: ResourceKind
    public var judgement: Judgement

    public init(resource: ResourceKind, judgement: Judgement) {
        self.resource = resource
        self.judgement = judgement
    }
}
