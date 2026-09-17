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
}
