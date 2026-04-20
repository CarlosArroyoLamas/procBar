import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppContext: ObservableObject {
    let configPath: URL

    init(configPath: URL) { self.configPath = configPath }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }
}
