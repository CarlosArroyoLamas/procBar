import XCTest
@testable import Procbar

final class WorktreeScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_discovers_direct_repo_and_nested_repos() throws {
        try makeGitRepo(at: root.appendingPathComponent("alpha"))
        try makeGitRepo(at: root.appendingPathComponent("beta/gamma"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-repo"),
            withIntermediateDirectories: true
        )

        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(roots: [root.path], excluded: [])

        let names = Set(result.map { $0.name })
        XCTAssertEqual(names, ["alpha", "gamma"])
    }

    func test_respects_excluded_paths() throws {
        try makeGitRepo(at: root.appendingPathComponent("alpha"))
        try makeGitRepo(at: root.appendingPathComponent("beta"))

        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(
            roots: [root.path],
            excluded: [root.appendingPathComponent("beta").path]
        )
        XCTAssertEqual(result.map { $0.name }, ["alpha"])
    }

    func test_recognizes_gitfile_worktree_pointer() throws {
        let wtDir = root.appendingPathComponent("linked-worktree")
        try FileManager.default.createDirectory(at: wtDir, withIntermediateDirectories: true)
        try "gitdir: /tmp/some-main/.git/worktrees/x".write(
            to: wtDir.appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )
        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(roots: [root.path], excluded: [])
        XCTAssertEqual(result.map { $0.name }, ["linked-worktree"])
    }

    func test_reads_branch_through_injected_reader() throws {
        let repo = root.appendingPathComponent("repo")
        try makeGitRepo(at: repo)
        let reader = FakeBranchReader(branches: [repo.path: "main"])
        let scanner = WorktreeScanner(branchReader: reader)
        let result = scanner.scan(roots: [root.path], excluded: [])
        XCTAssertEqual(result.first?.branch, "main")
    }

    private func makeGitRepo(at dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
    }
}

struct FakeBranchReader: GitBranchReading {
    let branches: [String: String]
    func currentBranch(at path: String) -> String? { branches[path] }
}
