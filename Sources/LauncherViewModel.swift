import AppKit
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { refreshResults() }
    }
    @Published private(set) var results: [SearchItem] = []
    @Published var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            onSettingsChanged?(settings)
        }
    }

    var onOpenPreferences: (() -> Void)?
    var onSettingsChanged: ((AppSettings) -> Void)?

    private let settingsStore: SettingsStore
    private let discoveryService: AppDiscoveryService
    private let launchHistoryStore: LaunchHistoryStore

    private var apps: [AppEntry] = []

    private var commands: [CommandEntry] {
        [
            CommandEntry(
                id: "meow.preferences",
                title: L10n.cmdPreferencesTitle,
                subtitle: L10n.cmdPreferencesSubtitle,
                keywords: ["settings", "preferences", "menu bar", "dock", "auto launch", "toggle",
                           "设置", "偏好设置", "菜单栏", "自动启动"]
            ),
            CommandEntry(
                id: "meow.quit",
                title: L10n.cmdQuitTitle,
                subtitle: L10n.cmdQuitSubtitle,
                keywords: ["quit", "exit", "退出"]
            ),
        ]
    }

    init(
        settingsStore: SettingsStore,
        discoveryService: AppDiscoveryService,
        launchHistoryStore: LaunchHistoryStore
    ) {
        self.settingsStore = settingsStore
        self.discoveryService = discoveryService
        self.launchHistoryStore = launchHistoryStore
        self.settings = settingsStore.load()
    }

    func load() {
        apps = discoveryService.discoverApplications()
        refreshResults()
    }

    /// Re-evaluates results with the current language bundle.
    func refresh() {
        refreshResults()
    }

    func activate(_ item: SearchItem) {
        switch item {
        case .app(let app):
            launchHistoryStore.recordLaunch(id: app.id)
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            refreshResults()
        case .command(let command):
            run(command)
        }
    }

    private func run(_ command: CommandEntry) {
        switch command.id {
        case "meow.preferences":
            onOpenPreferences?()
        case "meow.quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func refreshResults() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            results = commands.map(SearchItem.command) + apps.prefix(30).map(SearchItem.app)
            return
        }

        let matchedCommands = commands.compactMap { command -> (SearchItem, Int)? in
            let hay = ([command.title, command.subtitle] + command.keywords).joined(separator: " ").lowercased()
            guard hay.contains(q) else { return nil }
            return (.command(command), score(text: hay, query: q) + 15)
        }

        let matchedApps = apps.compactMap { app -> (SearchItem, Int)? in
            let hay = [app.name, app.bundleId ?? ""].joined(separator: " ").lowercased()
            guard hay.contains(q) else { return nil }
            let base = score(text: hay, query: q)
            let history = launchHistoryStore.score(for: app.id)
            return (.app(app), base + history)
        }

        results = (matchedCommands + matchedApps)
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.primaryText.localizedCaseInsensitiveCompare(rhs.0.primaryText) == .orderedAscending
            }
            .map { $0.0 }
    }

    private func score(text: String, query: String) -> Int {
        if text == query { return 120 }
        if text.hasPrefix(query) { return 90 }
        if text.contains(" \(query)") { return 70 }
        return 50
    }
}
