import AppKit
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    private let maxSearchResults = 80
    private let maxIdleResults = 20

    @Published var query: String = "" {
        didSet {
            guard !isResettingForHide else { return }
            refreshResults()
        }
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
    var onPasteClipboard: ((ClipboardEntry) -> Void)?
    var onLaunchApplication: ((AppEntry) -> Void)?

    private let settingsStore: SettingsStore
    private let discoveryService: AppDiscoveryService
    private let launchHistoryStore: LaunchHistoryStore
    private let clipboardStore: ClipboardStore
    private let currentBundleID = Bundle.main.bundleIdentifier?.lowercased()
    private let discoveryRefreshInterval: TimeInterval = 8

    private var apps: [AppEntry] = []
    private var lastDiscoveryAt: Date?
    private var isResettingForHide = false

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
        launchHistoryStore: LaunchHistoryStore,
        clipboardStore: ClipboardStore
    ) {
        self.settingsStore = settingsStore
        self.discoveryService = discoveryService
        self.launchHistoryStore = launchHistoryStore
        self.clipboardStore = clipboardStore
        settings = settingsStore.load()
    }

    func load() {
        _ = refreshInstalledApps(force: true)
    }

    /// Re-evaluates results with the current language bundle.
    func refresh() {
        refreshResults()
    }

    /// Refreshes installed app discovery; throttled by default to keep launcher opening snappy.
    @discardableResult
    func refreshInstalledApps(force: Bool = false) -> Bool {
        let now = Date()
        if !force,
           let lastDiscoveryAt,
           now.timeIntervalSince(lastDiscoveryAt) < discoveryRefreshInterval
        {
            return false
        }

        lastDiscoveryAt = now
        let discovered = discoveryService.discoverApplications().filter { !isCurrentApp($0) }
        apps = discovered
        refreshResults()
        return true
    }

    /// Resets transient launcher state without triggering another search pass while hiding.
    func resetForHide() {
        isResettingForHide = true
        query = ""
        isResettingForHide = false
        results = []
    }

    func deleteClipboardItem(_ item: SearchItem) {
        guard settings.clipboardHistoryEnabled else { return }
        guard case let .clipboard(entry) = item else { return }
        clipboardStore.delete(entry)
    }

    func copyClipboardItem(_ item: SearchItem) {
        guard settings.clipboardHistoryEnabled else { return }
        guard case let .clipboard(entry) = item else { return }
        clipboardStore.writeToPasteboard(entry)
    }

    func activate(_ item: SearchItem) {
        switch item {
        case let .app(app):
            launchHistoryStore.recordLaunch(id: app.id)
            if let onLaunchApplication {
                onLaunchApplication(app)
            } else {
                NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            // Clear results directly to reduce retained memory without triggering a full search refresh.
            results = []
        case let .command(command):
            run(command)
        case let .clipboard(entry):
            onPasteClipboard?(entry)
            results = []
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
            var idle: [SearchItem] = apps.prefix(maxIdleResults).map(SearchItem.app)
            if settings.clipboardHistoryEnabled {
                let recentClipboard = clipboardStore.getEntries().prefix(8).map(SearchItem.clipboard)
                idle += recentClipboard
            }
            results = idle
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

        let matchedClipboard: [(SearchItem, Int)]
        if settings.clipboardHistoryEnabled {
            matchedClipboard = clipboardStore.getEntries().compactMap { entry -> (SearchItem, Int)? in
                guard entry.preview.lowercased().contains(q) else { return nil }
                return (.clipboard(entry), 5)
            }
        } else {
            matchedClipboard = []
        }

        results = (matchedCommands + matchedApps + matchedClipboard)
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.primaryText.localizedCaseInsensitiveCompare(rhs.0.primaryText) == .orderedAscending
            }
            .prefix(maxSearchResults)
            .map { $0.0 }
    }

    private func score(text: String, query: String) -> Int {
        if text == query { return 120 }
        if text.hasPrefix(query) { return 90 }
        if text.contains(" \(query)") { return 70 }
        return 50
    }

    private func isCurrentApp(_ app: AppEntry) -> Bool {
        if let currentBundleID,
           let appBundleID = app.bundleId?.lowercased(),
           appBundleID == currentBundleID
        {
            return true
        }

        return false
    }
}
