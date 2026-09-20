import XCTest
@testable import Narrator

final class NarratorTests: XCTestCase {

    /// 어떤 기기에서도 사유를 돌려줄 뿐 멈추지 않는다 (A-01).
    func testAvailabilityAlwaysAnswers() {
        let availability = NarratorAvailability.current()
        if #unavailable(macOS 26) {
            XCTAssertEqual(availability, .unsupportedOS)
        } else {
            XCTAssertNotEqual(availability, .unsupportedOS)
        }
    }

    /// 쓸 수 없는 사유가 하나라도 있으면 모델을 부르지 않고 그 사유를 그대로 돌려준다.
    /// 가용성을 주입받는 이유가 이것이다. 이 테스트는 어느 기기에서 돌려도 모델을 건드리지 않는다.
    func testProbeSkipsGenerationWhenUnavailable() async {
        let reasons: [NarratorAvailability] = [
            .unsupportedOS, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .koreanNotSupported, .unavailable,
        ]
        for reason in reasons {
            let result = await NarratorProbe.generateOneSentence(availability: reason)
            XCTAssertEqual(result, .unavailable(reason))
        }
    }

    /// 프로브가 모델에 넘기는 값은 합성값이다. 실제 기기의 사용 기록을 프롬프트에 넣지 않는다.
    func testProbePromptUsesSyntheticNumbers() {
        XCTAssertTrue(NarratorProbe.prompt.contains("23%"))
        XCTAssertFalse(NarratorProbe.prompt.lowercased().contains("com."))
    }
}
