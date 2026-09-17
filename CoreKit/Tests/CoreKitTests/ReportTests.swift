import XCTest
import Model
@testable import Report

final class ReportTests: XCTestCase {

    private let report = CheckupReport(
        device: DeviceInfo(model: "Mac17,2", chip: "Apple M5", memoryBytes: 16 << 30),
        findings: [
            ResourceFinding(resource: .memory, judgement: .graded(.watch)),
            ResourceFinding(resource: .gpu, judgement: .withheld(.metricUnavailable)),
        ]
    )

    func testRoundTrip() throws {
        let data = try CheckupReport.encoder().encode(report)
        let decoded = try CheckupReport.decoder().decode(CheckupReport.self, from: data)
        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.schemaVersion, CheckupReport.currentSchemaVersion)
    }

    /// 같은 리포트는 같은 바이트 (F-33, F-52).
    func testEncodingIsStable() throws {
        let first = try CheckupReport.encoder().encode(report)
        let second = try CheckupReport.encoder().encode(report)
        XCTAssertEqual(first, second)
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("\"schema_version\" : 1"))
    }
}
