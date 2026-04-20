import Foundation
import os

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
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["git", "-C", path, "symbolic-ref", "--short", "HEAD"]
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            logger.error("git spawn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}
