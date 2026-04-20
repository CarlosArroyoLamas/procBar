import XCTest
import Combine
@testable import Procbar

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!
    private var path: URL!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        path = tempDir.appendingPathComponent("config.yaml")
        cancellables = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_loads_default_config_and_writes_file_when_missing() throws {
        let store = ConfigStore(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))

        let loaded = try store.loadOrCreateDefault()
        XCTAssertEqual(loaded, Config.defaultConfig())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func test_loads_existing_file() throws {
        try "refresh_interval_seconds: 5\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: path)
        let loaded = try store.loadOrCreateDefault()
        XCTAssertEqual(loaded.refreshIntervalSeconds, 5)
    }

    func test_invalid_yaml_surfaces_as_error_but_keeps_last_good() throws {
        try "refresh_interval_seconds: 2\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: path)
        _ = try store.loadOrCreateDefault()

        try "this is not: valid yaml: at all: \t\n  - : :"
            .write(to: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.reload())
        XCTAssertEqual(store.current.refreshIntervalSeconds, 2, "last-good retained")
    }

    func test_save_writes_yaml_that_roundtrips() throws {
        let store = ConfigStore(path: path)
        var cfg = try store.loadOrCreateDefault()
        cfg.refreshIntervalSeconds = 7
        try store.save(cfg)
        let reloaded = try store.reload()
        XCTAssertEqual(reloaded.refreshIntervalSeconds, 7)
    }

    func test_publishes_when_file_changes() throws {
        let store = ConfigStore(path: path)
        _ = try store.loadOrCreateDefault()
        store.startWatching()
        defer { store.stopWatching() }

        let exp = expectation(description: "external change published")
        store.changes.sink { _ in exp.fulfill() }.store(in: &cancellables)

        // External write
        try "refresh_interval_seconds: 9\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 3.0)
        XCTAssertEqual(store.current.refreshIntervalSeconds, 9)
    }
}
