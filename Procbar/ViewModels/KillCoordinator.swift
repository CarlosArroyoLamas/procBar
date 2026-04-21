import Foundation
import SwiftUI

@MainActor
final class KillCoordinator: ObservableObject {
    private let killer: ProcessKiller
    private let sourceFactory: () -> [RawProcess]

    init(killer: ProcessKiller, sourceFactory: @escaping () -> [RawProcess]) {
        self.killer = killer
        self.sourceFactory = sourceFactory
    }

    /// Graceful kill. Completion reports the real outcome so the UI's Stop
    /// button can distinguish ".exitedGracefully" (green flash) from
    /// ".escalatedToSigkill" (red flash).
    func gracefulKill(process: TrackedProcess, completion: @escaping (KillOutcome) -> Void) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.gracefulKill(tree: tree) { outcome in
            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }

    /// Immediate SIGKILL. Completion is invoked for symmetry with the
    /// graceful path; always reports `.forced`.
    func forceKill(process: TrackedProcess, completion: @escaping (KillOutcome) -> Void = { _ in }) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.forceKill(tree: tree) { outcome in
            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }
}
