import Foundation
import AppKit

/// Discovers `.app` bundles in the standard installation directories.
/// The scan is I/O-only (no heavy metadata parsing), so it's fast enough
/// to run synchronously every time the Settings window opens its Apps tab.
enum InstalledApps {
    struct Entry: Identifiable, Hashable {
        let name: String
        let path: String
        var id: String { path }
    }

    static func scan() -> [Entry] {
        let home = NSHomeDirectory() as NSString
        let directories = [
            "/Applications",
            "/System/Applications",
            home.appendingPathComponent("Applications")
        ]
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [Entry] = []

        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(entry)
                guard seen.insert(path).inserted else { continue }
                let name = String(entry.dropLast(4))
                results.append(Entry(name: name, path: path))
            }
        }

        // Also walk one level deep into /Applications for apps stashed in
        // subfolders (Utilities, Xcode bundle extras, etc.).
        let nested = ["/Applications", "/System/Applications"]
        for dir in nested {
            guard let subs = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for sub in subs {
                let subPath = (dir as NSString).appendingPathComponent(sub)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: subPath, isDirectory: &isDir),
                      isDir.boolValue,
                      !sub.hasSuffix(".app") else { continue }
                guard let inner = try? fm.contentsOfDirectory(atPath: subPath) else { continue }
                for entry in inner where entry.hasSuffix(".app") {
                    let path = (subPath as NSString).appendingPathComponent(entry)
                    guard seen.insert(path).inserted else { continue }
                    let name = String(entry.dropLast(4))
                    results.append(Entry(name: name, path: path))
                }
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
