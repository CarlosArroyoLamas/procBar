import XCTest
@testable import Procbar

final class GitBranchReaderTests: XCTestCase {
    func test_reads_branch_from_real_repo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = runGit(["init", "-b", "trunk"], cwd: dir.path)
        // Need at least one commit before symbolic-ref works reliably on some versions
        try "x".write(to: dir.appendingPathComponent("x"), atomically: true, encoding: .utf8)
        _ = runGit(["add", "."], cwd: dir.path)
        _ = runGit(["-c", "user.email=a@a", "-c", "user.name=a", "commit", "-m", "init"], cwd: dir.path)

        let reader = LiveGitBranchReader(ttlSeconds: 0)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "trunk")
    }

    func test_returns_nil_for_non_repo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = LiveGitBranchReader(ttlSeconds: 0)
        XCTAssertNil(reader.currentBranch(at: dir.path))
    }

    func test_caches_within_ttl() throws {
        // Hard to measure timing; smoke-check: calling twice returns same value even if the
        // underlying directory is removed between calls (cache returns stale).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = runGit(["init", "-b", "xx"], cwd: dir.path)
        try "x".write(to: dir.appendingPathComponent("x"), atomically: true, encoding: .utf8)
        _ = runGit(["add", "."], cwd: dir.path)
        _ = runGit(["-c", "user.email=a@a", "-c", "user.name=a", "commit", "-m", "init"], cwd: dir.path)

        let reader = LiveGitBranchReader(ttlSeconds: 60)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "xx")
        try FileManager.default.removeItem(at: dir)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "xx") // from cache
    }

    @discardableResult
    private func runGit(_ args: [String], cwd: String) -> Int32 {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["git"] + args
        p.currentDirectoryPath = cwd
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
