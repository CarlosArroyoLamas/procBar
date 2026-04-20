import Foundation

struct WorktreeGroup: Identifiable, Hashable {
    let worktree: Worktree
    let processes: [TrackedProcess]
    var id: String { worktree.path }
}
