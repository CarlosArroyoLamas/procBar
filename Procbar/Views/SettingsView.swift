import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appContext: AppContext
    @State private var cfg: Config = .defaultConfig()
    @State private var loadError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            rootsTab.tabItem { Label("Worktrees", systemImage: "folder") }
            patternsTab.tabItem { Label("Patterns", systemImage: "text.magnifyingglass") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear(perform: load)
    }

    private var generalTab: some View {
        Form {
            Stepper(value: $cfg.refreshIntervalSeconds, in: 1...30) {
                Text("Refresh interval: \(cfg.refreshIntervalSeconds) s")
            }
            Toggle("Show git branch in section headers", isOn: $cfg.showBranch)
            Toggle("Launch at login", isOn: $cfg.launchAtLogin)
                .onChange(of: cfg.launchAtLogin) { newValue in
                    LoginItem.setEnabled(newValue)
                    save()
                }
            Button("Open config file…") { appContext.openConfigFile() }
            if let err = loadError {
                Text(err)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Color.warning.swiftUI)
            }
        }
        .onChange(of: cfg.refreshIntervalSeconds) { _ in save() }
        .onChange(of: cfg.showBranch) { _ in save() }
    }

    private var rootsTab: some View {
        VStack(alignment: .leading) {
            Text("Worktree roots").font(DesignSystem.Typography.header)
            EditableListView(items: $cfg.worktreeRoots, placeholder: "~/Documents")
                .onChange(of: cfg.worktreeRoots) { _ in save() }
            Text("Excluded paths").font(DesignSystem.Typography.header).padding(.top, 12)
            EditableListView(items: $cfg.excludedPaths, placeholder: "~/Documents/archive")
                .onChange(of: cfg.excludedPaths) { _ in save() }
        }
    }

    private var patternsTab: some View {
        VStack(alignment: .leading) {
            Text("Process patterns").font(DesignSystem.Typography.header)
            Text("A process is tracked if its name or full command matches any pattern (case-insensitive substring).")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Color.textSecondary.swiftUI)
            PatternListView(patterns: $cfg.processPatterns)
                .onChange(of: cfg.processPatterns) { _ in save() }
        }
    }

    private func load() {
        do {
            let store = ConfigStore(path: appContext.configPath)
            cfg = try store.loadOrCreateDefault()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try ConfigStore(path: appContext.configPath).save(cfg)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct EditableListView: View {
    @Binding var items: [String]
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(items.indices, id: \.self) { i in
                HStack {
                    TextField(placeholder, text: $items[i])
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { items.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                }
            }
            Button("+ Add") { items.append("") }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        }
    }
}

private struct PatternListView: View {
    @Binding var patterns: [Config.Pattern]

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(patterns.indices, id: \.self) { i in
                HStack {
                    TextField("Display name", text: $patterns[i].name).frame(width: 120)
                    TextField("Match substring", text: $patterns[i].match).frame(width: 160)
                    Picker("", selection: $patterns[i].matchField) {
                        Text("command").tag(Config.MatchField.command)
                        Text("name").tag(Config.MatchField.name)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    Button(role: .destructive) { patterns.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                }
            }
            Button("+ Add pattern") {
                patterns.append(.init(name: "", match: "", matchField: .command))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        }
    }
}
