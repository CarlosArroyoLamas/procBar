import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppContext: ObservableObject {
    /// The canonical `ConfigStore` instance for the running app. Settings UI
    /// reads and writes through this one; ProcbarApp's bootstrap wires the
    /// file watcher on it so external edits flow back into the UI.
    let configStore: ConfigStore

    var configPath: URL { configStore.path }

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }
}
