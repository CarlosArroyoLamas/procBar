import Foundation

struct Worktree: Identifiable, Hashable {
    let path: String
    let name: String
    var branch: String?

    var id: String { path }
}
