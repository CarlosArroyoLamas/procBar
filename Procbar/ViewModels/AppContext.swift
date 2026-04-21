import Foundation
import AppKit
import SwiftUI
import os

@MainActor
final class AppContext: ObservableObject {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    /// The canonical `ConfigStore` instance for the running app. Settings UI
    /// reads and writes through this one; ProcbarApp's bootstrap wires the
    /// file watcher on it so external edits flow back into the UI.
    let configStore: ConfigStore

    var configPath: URL { configStore.path }

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    /// Opens the SwiftUI `Settings` scene window.
    ///
    /// For an `LSUIElement` app, the window doesn't exist on launch; we
    /// have to (1) activate the app so a window can become key, then
    /// (2) send the right selector for the running OS. In macOS 14 Apple
    /// renamed `showPreferencesWindow:` to `showSettingsWindow:`. A
    /// post-dispatch sweep finds the settings window by title and orders
    /// it to the front if the selector pathway failed silently.
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        let selector: Selector
        if #available(macOS 14.0, *) {
            selector = Selector(("showSettingsWindow:"))
        } else {
            selector = Selector(("showPreferencesWindow:"))
        }
        let dispatched = NSApp.sendAction(selector, to: nil, from: nil)
        logger.info("openSettings: selector=\(NSStringFromSelector(selector), privacy: .public) dispatched=\(dispatched)")

        // Fallback: give SwiftUI a run-loop turn to create/show the window,
        // then explicitly key any window matching the Settings title.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let titles = ["Settings", "Preferences"]
            if let win = NSApp.windows.first(where: { w in
                titles.contains(where: { w.title.contains($0) })
                    || w.identifier?.rawValue.contains("com_apple_SwiftUI_Settings_window") == true
            }) {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }
}
