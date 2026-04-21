import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appContext: AppContext
    @State private var cfg: Config
    @State private var loadError: String?
    @State private var launchAtLoginSystem: Bool = LoginItem.isEnabled

    init() {
        _cfg = State(initialValue: Config.defaultConfig())
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            rootsTab.tabItem { Label("Worktrees", systemImage: "folder") }
            patternsTab.tabItem { Label("Patterns", systemImage: "text.magnifyingglass") }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .onAppear(perform: load)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Stepper(value: $cfg.refreshIntervalSeconds, in: 1...30) {
                Text("Refresh interval: \(cfg.refreshIntervalSeconds) s")
            }
            Toggle("Show git branch in section headers", isOn: $cfg.showBranch)
            Toggle("Launch at login", isOn: $launchAtLoginSystem)

            Section {
                Button("Open config file…") { appContext.openConfigFile() }
                Text(appContext.configPath.path)
                    .font(DesignSystem.Typography.branch)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            } header: {
                Text("Raw YAML").font(DesignSystem.Typography.header)
            }

            if let err = loadError {
                Text(err)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Color.warning.swiftUI)
            }
        }
        .onChange(of: cfg.refreshIntervalSeconds) { _ in save() }
        .onChange(of: cfg.showBranch) { _ in save() }
        .onChange(of: launchAtLoginSystem) { newValue in
            LoginItem.setEnabled(newValue)
            cfg.launchAtLogin = newValue
            save()
        }
    }

    // MARK: - Worktrees

    private var rootsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "Worktree roots",
                    subtitle: "Directories scanned for git repositories. The app walks each up to 4 levels deep. Tilde is expanded."
                )
                EditablePathList(items: $cfg.worktreeRoots,
                                 placeholder: "~/Documents",
                                 addPrompt: "Add worktree root")
                    .onChange(of: cfg.worktreeRoots) { _ in save() }

                Divider()

                SectionHeader(
                    title: "Excluded paths",
                    subtitle: "Worktrees whose absolute path is inside one of these are skipped."
                )
                EditablePathList(items: $cfg.excludedPaths,
                                 placeholder: "~/Documents/archive",
                                 addPrompt: "Add excluded folder")
                    .onChange(of: cfg.excludedPaths) { _ in save() }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Patterns

    private var patternsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: "Process patterns",
                    subtitle: "A process is tracked if its name (comm) or its full command contains the pattern substring, case-insensitive. PID must also live inside a discovered worktree."
                )

                PatternPresetBar(patterns: $cfg.processPatterns)
                    .onChange(of: cfg.processPatterns) { _ in save() }

                Divider()

                PatternList(patterns: $cfg.processPatterns)
                    .onChange(of: cfg.processPatterns) { _ in save() }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - State

    private func load() {
        do {
            cfg = try appContext.configStore.loadOrCreateDefault()
            launchAtLoginSystem = LoginItem.isEnabled
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try appContext.configStore.save(cfg)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DesignSystem.Typography.header)
            Text(subtitle)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Color.textSecondary.swiftUI)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Editable path list (with folder picker)

private struct EditablePathList: View {
    @Binding var items: [String]
    let placeholder: String
    let addPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField(placeholder, text: $items[i])
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if let picked = FolderPicker.pick(prompt: "Choose") {
                            items[i] = picked
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Browse for a folder")
                    Button(role: .destructive) {
                        items.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }

            HStack(spacing: 10) {
                Button {
                    items.append("")
                } label: {
                    Label("Add empty", systemImage: "plus")
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accent.swiftUI)

                Button {
                    if let picked = FolderPicker.pick(prompt: addPrompt) {
                        items.append(picked)
                    }
                } label: {
                    Label("Browse…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Preset chips

private struct PresetPattern: Identifiable, Hashable {
    let name: String
    let match: String
    let field: Config.MatchField
    var id: String { "\(name)|\(match)|\(field.rawValue)" }
}

private struct PatternPresetBar: View {
    @Binding var patterns: [Config.Pattern]

    /// Common dev-server patterns. Clicking a chip appends the pattern if
    /// it isn't already present (by match + field). Order matters for the
    /// grid — most-used first.
    private let presets: [PresetPattern] = [
        .init(name: "Node",     match: "node",                 field: .name),
        .init(name: "Vite",     match: "vite",                 field: .command),
        .init(name: "NX",       match: "nx",                   field: .command),
        .init(name: "Next",     match: "next dev",             field: .command),
        .init(name: "Webpack",  match: "webpack",              field: .command),
        .init(name: "Esbuild",  match: "esbuild",              field: .command),
        .init(name: "Rollup",   match: "rollup",               field: .command),
        .init(name: "Postgres", match: "postgres",             field: .name),
        .init(name: "MySQL",    match: "mysqld",               field: .name),
        .init(name: "Redis",    match: "redis-server",         field: .name),
        .init(name: "Mongo",    match: "mongod",               field: .name),
        .init(name: "Python",   match: "python",               field: .name),
        .init(name: "Flask",    match: "flask",                field: .command),
        .init(name: "Django",   match: "manage.py runserver",  field: .command),
        .init(name: "Rails",    match: "rails server",         field: .command),
        .init(name: "Ruby",     match: "ruby",                 field: .name),
        .init(name: "Go",       match: "go run",               field: .command),
        .init(name: "Cargo",    match: "cargo run",            field: .command),
        .init(name: "Bun",      match: "bun",                  field: .command),
        .init(name: "Deno",     match: "deno",                 field: .command),
    ]

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK ADD")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(presets) { preset in
                    PresetChip(preset: preset, added: isAdded(preset)) {
                        toggle(preset)
                    }
                }
            }
        }
    }

    private func isAdded(_ preset: PresetPattern) -> Bool {
        patterns.contains {
            $0.match.lowercased() == preset.match.lowercased() && $0.matchField == preset.field
        }
    }

    private func toggle(_ preset: PresetPattern) {
        if let idx = patterns.firstIndex(where: {
            $0.match.lowercased() == preset.match.lowercased() && $0.matchField == preset.field
        }) {
            patterns.remove(at: idx)
        } else {
            patterns.append(.init(name: preset.name, match: preset.match, matchField: preset.field))
        }
    }
}

private struct PresetChip: View {
    let preset: PresetPattern
    let added: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(added
              ? "Already added — click to remove"
              : "Add pattern: \(preset.match) in \(preset.field.rawValue)")
    }

    private var background: Color {
        if added { return DesignSystem.Color.success.swiftUI.opacity(0.16) }
        return hovering
            ? DesignSystem.Color.accent.swiftUI.opacity(0.20)
            : DesignSystem.Color.accent.swiftUI.opacity(0.10)
    }
    private var foreground: Color {
        added ? DesignSystem.Color.success.swiftUI : DesignSystem.Color.accent.swiftUI
    }
    private var borderColor: Color {
        foreground.opacity(0.35)
    }
}

// MARK: - Custom pattern list

private struct PatternList: View {
    @Binding var patterns: [Config.Pattern]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CUSTOM PATTERNS")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)

            if patterns.isEmpty {
                Text("No patterns yet — click a preset above or add one below.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            }

            ForEach(patterns.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField("Display name", text: $patterns[i].name)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                    TextField("Match substring", text: $patterns[i].match)
                        .frame(width: 180)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $patterns[i].matchField) {
                        Text("command").tag(Config.MatchField.command)
                        Text("name").tag(Config.MatchField.name)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Button(role: .destructive) {
                        patterns.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                patterns.append(.init(name: "", match: "", matchField: .command))
            } label: {
                Label("Add custom pattern", systemImage: "plus")
                    .font(DesignSystem.Typography.bodyRegular)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        }
    }
}

// MARK: - Folder picker helper

private enum FolderPicker {
    /// Shows an NSOpenPanel; returns the picked path with home abbreviated
    /// to `~`. Returns nil if the user cancelled.
    static func pick(prompt: String) -> String? {
        let panel = NSOpenPanel()
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return abbreviatingHome(url.path)
    }

    private static func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
