import XCTest
@testable import Store

/// 임시 디렉터리에서만 연다. 사용자의 `~/Library/Application Support/JinMac/`은 건드리지 않는다.
final class StoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinMacStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOpensInWALModeAtCurrentSchemaVersion() async throws {
        let store = try SampleStore(directory: directory)
        let mode = try await store.journalMode()
        let version = try await store.userVersion()
        XCTAssertEqual(mode, "wal")
        XCTAssertEqual(version, SampleStore.schemaVersion)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(SampleStore.fileName).path))
    }

    func testDataDirectoryOverride() {
        let url = SampleStore.defaultDirectory(environment: ["JINMAC_DATA_DIR": "/tmp/jinmac-test"])
        XCTAssertEqual(url.path, "/tmp/jinmac-test")
    }

    func testDefaultDirectoryIsApplicationSupport() {
        let url = SampleStore.defaultDirectory(environment: [:])
        XCTAssertEqual(url.lastPathComponent, "JinMac")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Application Support")
    }
}
