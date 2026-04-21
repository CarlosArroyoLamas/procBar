import SwiftUI
import Combine

@main
struct ProcbarApp: App {
    @StateObject private var vm: AppViewModel
    @StateObject private var appContext: AppContext
    @StateObject private var killCoordinator: KillCoordinator

    /// Reference-typed subscription holder so the App struct can retain
    /// Combine pipelines across its lifetime without needing to mutate
    /// itself from init.
    private let subscriptions = SubscriptionBag()

    @MainActor
    init() {
        // Bootstrap config. Surfacing a first-run or parse error to the UI
        // requires the view model, so capture the message and set it after
        // the model is constructed.
        let path = ConfigStore.defaultPath
        let store = ConfigStore(path: path)
        var initialError: String?
        do {
            _ = try store.loadOrCreateDefault()
        } catch {
            initialError = error.localizedDescription
        }

        // Single libproc instance shared between the scanner and the
        // kill-coordinator's PID-tree builder. Having two was harmless today
        // but would be a foot-gun if the source ever caches.
        let source = LibprocSource()
        let scanner = ProcessScanner(source: source)
        let worktreeScanner = WorktreeScanner(branchReader: LiveGitBranchReader())

        let ctx = AppContext(configStore: store)
        let killer = ProcessKiller(sender: SystemKillSender())
        let coord = KillCoordinator(killer: killer, sourceFactory: { source.listAll() })

        // Providers read through `store.current` (thread-safe) each call so
        // config edits flow in without rewiring. The view model caches the
        // worktree scan result with a TTL so we don't fs-walk every tick.
        let configProvider: () -> Config = { store.current }
        let worktreesProvider: () -> [Worktree] = {
            worktreeScanner.scan(
                roots: store.current.worktreeRoots,
                excluded: store.current.excludedPaths
            )
        }

        let viewModel = AppViewModel(
            scanner: scanner,
            worktreesProvider: worktreesProvider,
            configProvider: configProvider
        )
        viewModel.configError = initialError

        _vm = StateObject(wrappedValue: viewModel)
        _appContext = StateObject(wrappedValue: ctx)
        _killCoordinator = StateObject(wrappedValue: coord)

        // Reconcile launch-at-login with YAML intent on startup. SMAppService
        // calls are cheap no-ops when the state already matches.
        LoginItem.setEnabled(store.current.launchAtLogin)

        // Arm the file watcher so external edits flow in.
        store.startWatching()

        // Subscribe to config changes. Timer cadence depends on
        // refreshIntervalSeconds; restart the polling loop whenever config
        // reloads. Also invalidate the worktree cache in case roots changed.
        let bag = subscriptions
        store.changes
            .receive(on: RunLoop.main)
            .sink { cfg in
                MainActor.assumeIsolated {
                    viewModel.invalidateWorktreeCache()
                    viewModel.stop()
                    viewModel.start()
                    // Reconcile login state on config reload too.
                    LoginItem.setEnabled(cfg.launchAtLogin)
                }
            }
            .store(in: &bag.cancellables)

        // Subscribe to parse errors so the "CONFIG ERROR" pill surfaces
        // real-time edits, not just first-run state.
        store.errors
            .receive(on: RunLoop.main)
            .sink { message in
                MainActor.assumeIsolated {
                    viewModel.configError = message
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
            MenuBarLabel()
                .environmentObject(vm)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appContext)
        }
    }
}

/// Menu bar icon view. Dims when idle (no tracked processes) and overlays a
/// small amber dot when the config file fails to parse.
private struct MenuBarLabel: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .opacity(vm.isActive ? 1.0 : 0.4)
            .overlay(alignment: .bottomTrailing) {
                if vm.configError != nil {
                    Circle()
                        .fill(DesignSystem.Color.accent.swiftUI)
                        .frame(width: 4, height: 4)
                        .offset(x: 1, y: 1)
                }
            }
    }
}

/// Holder so a `struct App` can accumulate Combine cancellables from `init`
/// without making itself mutable.
private final class SubscriptionBag {
    var cancellables = Set<AnyCancellable>()
}
