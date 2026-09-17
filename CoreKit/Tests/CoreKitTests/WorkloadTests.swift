import XCTest
@testable import Workload

final class WorkloadTests: XCTestCase {

    /// F-20의 카테고리 10종.
    func testTenCategories() {
        XCTAssertEqual(WorkloadCategory.allCases.count, 10)
    }

    func testBundledMapDecodes() throws {
        let map = try CategoryMap.bundled()
        XCTAssertEqual(map.schemaVersion, 1)
    }

    func testUnknownAppIsOther() {
        let map = CategoryMap(schemaVersion: 1, apps: ["com.apple.dt.Xcode": .development])
        XCTAssertEqual(map.category(for: "com.apple.dt.Xcode"), .development)
        XCTAssertEqual(map.category(for: "com.example.unknown"), .other)
    }
}
