import Foundation

enum PathUtils {
    static func expand(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst(1)) }
        return path
    }

    /// Is `child` equal to `parent` or inside it (by path component, not substring)?
    static func isInside(child: String, parent: String) -> Bool {
        let c = normalize(child)
        let p = normalize(parent)
        if c == p { return true }
        return c.hasPrefix(p + "/")
    }

    private static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        var s = path
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
