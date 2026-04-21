import Foundation
import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class AppContext: ObservableObject {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    /// The canonical `ConfigStore` instance for the running app. Settings UI
    /// reads and writes through this one; ProcbarApp's bootstrap wires the
    /// file watcher on it so external edits flow back into the UI.
    let configStore: ConfigStore

    /// Token for the NSWindow.willCloseNotification observer. Held so we can
    /// un-observe (and drop the activation-policy reset) if needed.
    private var closeObserver: NSObjectProtocol?

    var configPath: URL { configStore.path }

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    /// Opens the SwiftUI `Settings` scene window.
    ///
    /// `LSUIElement` apps declare activationPolicy = .accessory, meaning
    /// they can't own a key window. The Settings scene's selector
    /// (`showSettingsWindow:` on macOS 14+, `showPreferencesWindow:` on 13)
    /// is dispatched but the resulting window fails to become visible
    /// because .accessory apps can't have ordered-front windows.
    ///
    /// The workaround is to promote the policy to .regular for the duration
    /// the Settings window is open, then drop back to .accessory when it
    /// closes. Dock briefly gains an icon; that's acceptable for a settings
    /// panel and the only way to get a reliable, key-focused window.
    func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let selector: Selector
        if #available(macOS 14.0, *) {
            selector = Selector(("showSettingsWindow:"))
        } else {
            selector = Selector(("showPreferencesWindow:"))
        }
        let dispatched = NSApp.sendAction(selector, to: nil, from: nil)
        logger.info("openSettings: selector=\(NSStringFromSelector(selector), privacy: .public) dispatched=\(dispatched)")

        // Find the Settings window after SwiftUI has had a chance to create
        // it, force it to be key, and install a close observer so we can
        // drop back to .accessory when the user dismisses it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let candidate = NSApp.windows.first { w in
                let title = w.title
                let id = w.identifier?.rawValue ?? ""
                return title.contains("Settings")
                    || title.contains("Preferences")
                    || id.contains("com_apple_SwiftUI_Settings_window")
            }
            if let win = candidate {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.logger.info("openSettings: fronting window title=\(win.title, privacy: .public)")
                self.watchForClose(win)
            } else {
                self.logger.error("openSettings: no Settings window found after dispatch")
                // Nothing to restore to, but drop the policy so we don't
                // leave the Dock icon around.
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }

    private func watchForClose(_ window: NSWindow) {
        if let existing = closeObserver {
            NotificationCenter.default.removeObserver(existing)
            closeObserver = nil
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            if let token = self?.closeObserver {
                NotificationCenter.default.removeObserver(token)
                self?.closeObserver = nil
            }
        }
    }
}
