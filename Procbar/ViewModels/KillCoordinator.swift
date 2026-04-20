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

    func gracefulKill(process: TrackedProcess, completion: @escaping (Bool) -> Void) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.gracefulKill(tree: tree) {
            DispatchQueue.main.async {
                completion(true)
            }
        }
    }

    func forceKill(process: TrackedProcess) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.forceKill(tree: tree)
    }
}
