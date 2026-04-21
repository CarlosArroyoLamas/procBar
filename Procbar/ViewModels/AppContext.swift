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

    var configPath: URL { configStore.path }

    /// Lazily-built NSWindow hosting `SettingsView`. We build our own
    /// window rather than relying on the SwiftUI `Settings { ... }` scene,
    /// because on `LSUIElement` menu bar apps the `Settings` scene's
    /// selector path (`showSettingsWindow:`) silently fails to materialize
    /// a window — the selector returns handled, but no window is ever
    /// added to `NSApp.windows`.
    private var settingsWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    /// Opens (or brings to front) the Settings window.
    ///
    /// Strategy:
    ///   1. Promote activation policy to `.regular` so the window can key.
    ///      LSUIElement apps run as `.accessory` and can't own a key window.
    ///   2. Either show the cached window or build a new one via
    ///      `NSHostingController(rootView: SettingsView())`.
    ///   3. When the window closes, drop back to `.accessory` so the Dock
    ///      icon goes away, and release the window so the next open is
    ///      fresh.
    func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            logger.info("openSettings: reusing existing window")
            return
        }

        let rootView = SettingsView().environmentObject(self)
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Procbar Settings"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 620, height: 520))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        settingsWindow = win
        logger.info("openSettings: created new Settings window")

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.settingsWindow = nil
            if let token = self?.closeObserver {
                NotificationCenter.default.removeObserver(token)
                self?.closeObserver = nil
            }
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }
}
