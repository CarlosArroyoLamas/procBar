import Foundation
import Darwin
import os

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

    /// Sends SIGTERM to every PID, waits `graceSeconds`, then SIGKILL to survivors.
    /// Completion is called on the internal queue when the sequence finishes.
    func gracefulKill(tree pids: [Int32], completion: (() -> Void)? = nil) {
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
            if !allGone {
                for pid in pids where self.sender.isAlive(pid) {
                    self.sender.sigkill(pid)
                }
            }
            completion?()
        }
    }

    /// Immediate escalation (used for second-click fast path).
    func forceKill(tree pids: [Int32], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for pid in pids { self.sender.sigkill(pid) }
            completion?()
        }
    }
}
