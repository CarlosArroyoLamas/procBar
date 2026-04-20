import Foundation
import os

protocol GitBranchReading {
    func currentBranch(at path: String) -> String?
}

final class WorktreeScanner {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")
    private let branchReader: GitBranchReading
    private let maxDepth: Int

    init(branchReader: GitBranchReading, maxDepth: Int = 4) {
        self.branchReader = branchReader
        self.maxDepth = maxDepth
    }

    func scan(roots: [String], excluded: [String]) -> [Worktree] {
        var out: [Worktree] = []
        let fm = FileManager.default
        let excludedResolved = excluded.map(PathUtils.expand)
        for raw in roots {
            let root = PathUtils.expand(raw)
            guard fm.fileExists(atPath: root) else { continue }
            walk(root, depth: 0, excluded: excludedResolved, into: &out)
        }
        // Dedupe by path
        var seen = Set<String>()
        return out.filter { seen.insert($0.path).inserted }
    }

    private func walk(_ dir: String, depth: Int, excluded: [String], into out: inout [Worktree]) {
        if depth > maxDepth { return }
        if excluded.contains(where: { PathUtils.isInside(child: dir, parent: $0) }) { return }

        let dotGit = (dir as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
            let name = (dir as NSString).lastPathComponent
            let branch = branchReader.currentBranch(at: dir)
            out.append(Worktree(path: dir, name: name, branch: branch))
            return  // don't recurse into a repo's subfolders
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries {
            if entry.hasPrefix(".") { continue }
            let sub = (dir as NSString).appendingPathComponent(entry)
            var isSubDir: ObjCBool = false
            if fm.fileExists(atPath: sub, isDirectory: &isSubDir), isSubDir.boolValue {
                walk(sub, depth: depth + 1, excluded: excluded, into: &out)
            }
        }
    }
}
