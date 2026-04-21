import Foundation
import os

/// Reads the current branch for a git working directory by parsing the
/// `.git/HEAD` file directly. This avoids spawning `/usr/bin/env git` for
/// every worktree on every tick (potentially blocking for tens of ms each).
///
/// For linked worktrees (where `.git` is a file containing `gitdir: ...`),
/// the function follows the pointer to read that worktree's own HEAD.
/// Results are cached per path for `ttlSeconds`.
final class LiveGitBranchReader: GitBranchReading {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")
    private let ttlSeconds: TimeInterval
    private var cache: [String: (branch: String?, stamp: Date)] = [:]
    private let lock = NSLock()

    init(ttlSeconds: TimeInterval = 10) {
        self.ttlSeconds = ttlSeconds
    }

    func currentBranch(at path: String) -> String? {
        lock.lock()
        if let cached = cache[path], Date().timeIntervalSince(cached.stamp) < ttlSeconds {
            lock.unlock()
            return cached.branch
        }
        lock.unlock()

        let branch = readBranch(at: path)
        lock.lock()
        cache[path] = (branch, Date())
        lock.unlock()
        return branch
    }

    private func readBranch(at path: String) -> String? {
        let headURL = resolveHeadURL(for: path)
        guard let headURL else { return nil }

        guard let data = try? Data(contentsOf: headURL),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A branch HEAD looks like: "ref: refs/heads/<name>"
        // A detached HEAD is a raw commit SHA (no "ref:" prefix).
        if line.hasPrefix("ref: refs/heads/") {
            let branch = String(line.dropFirst("ref: refs/heads/".count))
            return branch.isEmpty ? nil : branch
        }
        // Detached HEAD — return nil rather than a 40-char SHA; spec says
        // branch name is optional and should simply be omitted when absent.
        return nil
    }

    /// Given a worktree path, returns the URL of the HEAD file that applies
    /// to it:
    ///   - `<path>/.git` is a directory → `<path>/.git/HEAD`
    ///   - `<path>/.git` is a file containing `gitdir: <p>` → `<p>/HEAD`
    /// Returns nil for non-repositories or unreadable gitdir pointers.
    private func resolveHeadURL(for path: String) -> URL? {
        let fm = FileManager.default
        let dotGit = URL(fileURLWithPath: path).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return dotGit.appendingPathComponent("HEAD")
        }
        // .git is a file with format: "gitdir: <absolute-or-relative-path>"
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }
        let raw = trimmed.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let target: URL
        if raw.hasPrefix("/") {
            target = URL(fileURLWithPath: raw)
        } else {
            target = URL(fileURLWithPath: path).appendingPathComponent(raw)
        }
        return target.appendingPathComponent("HEAD")
    }
}
