import Foundation
import Darwin
import os

enum KillOutcome: Equatable {
    /// All PIDs in the tree exited within the grace period after SIGTERM.
    case exitedGracefully
    /// Grace period elapsed; surviving PIDs received SIGKILL.
    case escalatedToSigkill
    /// `forceKill` path — SIGKILL sent immediately without SIGTERM.
    case forced
}

protocol KillSender {
    func sigterm(_ pid: Int32)
    func sigkill(_ pid: Int32)
    func isAlive(_ pid: Int32) -> Bool
}

final class SystemKillSender: KillSender {
    func sigterm(_ pid: Int32) { _ = kill(pid, SIGTERM) }
    func sigkill(_ pid: Int32) { _ = kill(pid, SIGKILL) }
    func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
}

final class ProcessKiller {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "kill")
    private let sender: KillSender
    private let graceSeconds: Double
    private let queue = DispatchQueue(label: "com.carlos.procbar.kill")

    init(sender: KillSender = SystemKillSender(), graceSeconds: Double = 3.0) {
        self.sender = sender
        self.graceSeconds = graceSeconds
    }

    static func tree(rootPID: Int32, among raw: [RawProcess]) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for p in raw { children[p.ppid, default: []].append(p.pid) }
        var out: [Int32] = []
        var seen: Set<Int32> = []
        var stack: [Int32] = [rootPID]
        while let top = stack.popLast() {
            if seen.insert(top).inserted {
                out.append(top)
                stack.append(contentsOf: children[top] ?? [])
            }
        }
        return out
    }

    /// Sends SIGTERM to every PID, polls for up to `graceSeconds`, then
    /// SIGKILLs survivors. Completion reports the actual outcome (whether
    /// SIGKILL was needed) so the UI can distinguish "exited on its own"
    /// from "had to be force-killed".
    func gracefulKill(tree pids: [Int32], completion: ((KillOutcome) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for pid in pids { self.sender.sigterm(pid) }
            let deadline = DispatchTime.now() + self.graceSeconds
            let pollInterval: Double = 0.1
            var allGone = false
            while DispatchTime.now() < deadline {
                if pids.allSatisfy({ !self.sender.isAlive($0) }) { allGone = true; break }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            let outcome: KillOutcome
            if allGone {
                outcome = .exitedGracefully
            } else {
                for pid in pids where self.sender.isAlive(pid) {
                    self.sender.sigkill(pid)
                }
                outcome = .escalatedToSigkill
            }
            completion?(outcome)
        }
    }

    /// Immediate escalation (used for the second-click fast path).
    func forceKill(tree pids: [Int32], completion: ((KillOutcome) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for pid in pids { self.sender.sigkill(pid) }
            completion?(.forced)
        }
    }
}
