import SwiftUI
import Combine

@main
struct ProcbarApp: App {
    @StateObject private var vm: AppViewModel
    @StateObject private var appContext: AppContext
    @StateObject private var killCoordinator: KillCoordinator

    private let configStore: ConfigStore
    private let worktreeScanner = WorktreeScanner(branchReader: LiveGitBranchReader())
    private let processScanner: ProcessScanner
    private let processSource = LibprocSource()

    // NOTE: Plan stored cancellables as a local `var` inside init; that would
    // cancel the subscription the instant init returns. Keep it as a stored
    // property so the Combine chain stays alive for the lifetime of the app.
    private let subscriptions = SubscriptionBag()

    @MainActor
    init() {
        let path = ConfigStore.defaultPath
        let store = ConfigStore(path: path)
        self.configStore = store

        // Bootstrap config or surface error to UI.
        var initialError: String?
        do {
            _ = try store.loadOrCreateDefault()
        } catch {
            initialError = error.localizedDescription
        }

        let source = LibprocSource()
        let scanner = ProcessScanner(source: source)
        self.processScanner = scanner

        let ctx = AppContext(configPath: path)

        let killer = ProcessKiller(sender: SystemKillSender())
        let coord = KillCoordinator(killer: killer, sourceFactory: { source.listAll() })

        let scannerCapture = worktreeScanner
        let worktreesProvider: () -> [Worktree] = {
            scannerCapture.scan(
                roots: store.current.worktreeRoots,
                excluded: store.current.excludedPaths
            )
        }
        let configProvider: () -> Config = { store.current }

        let viewModel = AppViewModel(
            scanner: scanner,
            worktreesProvider: worktreesProvider,
            configProvider: configProvider
        )
        viewModel.configError = initialError

        _vm = StateObject(wrappedValue: viewModel)
        _appContext = StateObject(wrappedValue: ctx)
        _killCoordinator = StateObject(wrappedValue: coord)

        store.startWatching()

        // Wire reloads (timer cadence might need to change on config change).
        // The sink closure runs on the main RunLoop, so hop to MainActor to
        // call the isolated stop()/start() pair safely under Swift 6.
        let bag = subscriptions
        store.changes
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    viewModel.stop()
                    viewModel.start()
                }
            }
            .store(in: &bag.cancellables)

        viewModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(vm)
                .environmentObject(appContext)
                .environmentObject(killCoordinator)
        } label: {
            Image("MenuBarIcon").renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appContext)
        }
    }
}

/// Reference-typed holder so a `struct App` can mutate a Combine cancellable
/// set from `init` without declaring the App stored property itself as `var`.
private final class SubscriptionBag {
    var cancellables = Set<AnyCancellable>()
}
