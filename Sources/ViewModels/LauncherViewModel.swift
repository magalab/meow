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
    var onOpenAIChat: ((AIChatInitialInput?) -> Void)?
    var onOpenAuthenticator: (() -> Void)?
    var onHealthCommand: ((HealthReminderCommand) -> Void)?
    var onScreenshotCommand: ((ScreenshotCommand) -> Void)?
    var onRecordingCommand: ((RecordingCommand) -> Void)?
    var onSpeakText: ((String) -> Void)?
    var onSpeakSelectedText: (() -> Void)?
    var onPinClipboardImage: ((ImageClipboardContent) -> Void)?
    var onRecognizeClipboardImage: ((ImageClipboardContent) -> Void)?
    var onTranslateClipboardImage: ((ImageClipboardContent) -> Void)?
    var onScanClipboardImageQRCode: ((ImageClipboardContent) -> Void)?
    var onEditClipboardImage: ((ImageClipboardContent) -> Void)?
    var onOpenClipboardImage: ((ImageClipboardContent) -> Void)?
    var onSaveClipboardImage: ((ImageClipboardContent) -> Void)?
    var onUploadClipboard: (() -> Void)?

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
        var entries = [
            CommandEntry(
                id: "meow.preferences",
                title: L10n.cmdPreferencesTitle,
                subtitle: L10n.cmdPreferencesSubtitle,
                keywords: ["settings", "preferences", "menu bar", "dock", "auto launch", "toggle",
                           "设置", "偏好设置", "菜单栏", "自动启动"]
            ),
            CommandEntry(
                id: "meow.ai.chat",
                title: L10n.cmdAIChatTitle,
                subtitle: L10n.cmdAIChatSubtitle,
                keywords: ["ai", "chat", "ask", "assistant", "summarize", "rewrite",
                           "人工智能", "聊天", "助手", "总结", "改写"]
            ),
            CommandEntry(
                id: "meow.health.start",
                title: L10n.cmdHealthStartTitle,
                subtitle: L10n.cmdHealthStartSubtitle,
                keywords: ["health", "focus", "timer", "work", "break", "start",
                           "健康", "专注", "计时", "休息", "开始"]
            ),
            CommandEntry(
                id: "meow.health.pause",
                title: L10n.cmdHealthPauseTitle,
                subtitle: L10n.cmdHealthPauseSubtitle,
                keywords: ["health", "pause", "resume", "focus", "timer",
                           "健康", "暂停", "继续", "专注", "计时"]
            ),
            CommandEntry(
                id: "meow.health.break",
                title: L10n.cmdHealthBreakTitle,
                subtitle: L10n.cmdHealthBreakSubtitle,
                keywords: ["health", "break", "rest", "stretch",
                           "健康", "休息", "伸展"]
            ),
            CommandEntry(
                id: "meow.health.skip",
                title: L10n.cmdHealthSkipTitle,
                subtitle: L10n.cmdHealthSkipSubtitle,
                keywords: ["health", "skip", "break", "rest",
                           "健康", "跳过", "休息"]
            ),
            CommandEntry(
                id: "meow.quit",
                title: L10n.cmdQuitTitle,
                subtitle: L10n.cmdQuitSubtitle,
                keywords: ["quit", "exit", "退出"]
            ),
        ]
        if settings.authenticatorEnabled {
            entries.insert(
                CommandEntry(
                    id: "meow.authenticator",
                    title: L10n.cmdAuthenticatorTitle,
                    subtitle: L10n.cmdAuthenticatorSubtitle,
                    keywords: ["totp", "2fa", "otp", "authenticator", "code",
                               "验证码", "两步验证", "动态口令", "认证器", "身份验证器"]
                ),
                at: 2
            )
        }
        if settings.fileHosting.s3.isEnabled {
            entries.insert(
                CommandEntry(
                    id: "meow.upload.clipboard",
                    title: L10n.cmdUploadClipboardTitle,
                    subtitle: L10n.cmdUploadClipboardSubtitle,
                    keywords: ["upload", "file", "image", "clipboard", "上传", "文件", "图片", "剪贴板"]
                ),
                at: min(2, entries.count)
            )
        }
        if settings.screenshot.enabled {
            entries.insert(
                contentsOf: [
                    CommandEntry(
                        id: "meow.screenshot.region",
                        title: L10n.cmdScreenshotRegionTitle,
                        subtitle: L10n.cmdScreenshotRegionSubtitle,
                        keywords: ["screenshot", "capture", "region", "area", "截图", "截屏", "区域截图"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.window",
                        title: L10n.cmdScreenshotWindowTitle,
                        subtitle: L10n.cmdScreenshotWindowSubtitle,
                        keywords: ["screenshot", "capture", "window", "截图", "截屏", "窗口截图"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.edit",
                        title: L10n.cmdScreenshotEditTitle,
                        subtitle: L10n.cmdScreenshotEditSubtitle,
                        keywords: ["screenshot", "capture", "edit", "annotate",
                                   "截图", "编辑截图", "标注"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.display",
                        title: L10n.cmdScreenshotDisplayTitle,
                        subtitle: L10n.cmdScreenshotDisplaySubtitle,
                        keywords: ["screenshot", "capture", "display", "screen", "full screen",
                                   "截图", "截屏", "全屏截图", "显示器"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.history",
                        title: L10n.cmdScreenshotHistoryTitle,
                        subtitle: L10n.cmdScreenshotHistorySubtitle,
                        keywords: ["screenshot", "capture", "history", "截图", "截图历史"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.ocr.latest",
                        title: L10n.cmdScreenshotOCRTitle,
                        subtitle: L10n.cmdScreenshotOCRSubtitle,
                        keywords: ["screenshot", "image", "ocr", "recognize", "text",
                                   "截图", "图片", "文字识别", "提取文字"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.translate.latest",
                        title: L10n.cmdScreenshotTranslateTitle,
                        subtitle: L10n.cmdScreenshotTranslateSubtitle,
                        keywords: ["screenshot", "image", "ocr", "translate",
                                   "截图", "图片", "翻译", "识别翻译"]
                    ),
                    CommandEntry(
                        id: "meow.screenshot.pin.latest",
                        title: L10n.cmdScreenshotPinTitle,
                        subtitle: L10n.cmdScreenshotPinSubtitle,
                        keywords: ["screenshot", "image", "clipboard", "pin", "float",
                                   "截图", "图片", "剪贴板", "贴图", "置顶"]
                    ),
                ],
                at: min(2, entries.count)
            )
        }
        if settings.recording.enabled {
            entries.insert(
                contentsOf: [
                    CommandEntry(
                        id: "meow.recording.display",
                        title: L10n.cmdRecordingDisplayTitle,
                        subtitle: L10n.cmdRecordingDisplaySubtitle,
                        keywords: ["record", "screen", "display", "录屏", "屏幕录制", "显示器"]
                    ),
                    CommandEntry(
                        id: "meow.recording.region",
                        title: L10n.cmdRecordingRegionTitle,
                        subtitle: L10n.cmdRecordingRegionSubtitle,
                        keywords: ["record", "region", "area", "录屏", "区域录制"]
                    ),
                    CommandEntry(
                        id: "meow.recording.window",
                        title: L10n.cmdRecordingWindowTitle,
                        subtitle: L10n.cmdRecordingWindowSubtitle,
                        keywords: ["record", "window", "录屏", "窗口录制"]
                    ),
                    CommandEntry(
                        id: "meow.recording.windows",
                        title: L10n.cmdRecordingWindowsTitle,
                        subtitle: L10n.cmdRecordingWindowsSubtitle,
                        keywords: ["record", "multiple", "windows", "录屏", "多个窗口", "多窗口"]
                    ),
                    CommandEntry(
                        id: "meow.recording.application",
                        title: L10n.cmdRecordingApplicationTitle,
                        subtitle: L10n.cmdRecordingApplicationSubtitle,
                        keywords: ["record", "application", "app", "录屏", "应用录制"]
                    ),
                    CommandEntry(
                        id: "meow.recording.audio",
                        title: L10n.cmdRecordingAudioTitle,
                        subtitle: L10n.cmdRecordingAudioSubtitle,
                        keywords: ["record", "system audio", "sound", "录音", "系统音频"]
                    ),
                    CommandEntry(
                        id: "meow.recording.history",
                        title: L10n.cmdRecordingHistoryTitle,
                        subtitle: L10n.cmdRecordingHistorySubtitle,
                        keywords: ["recording", "history", "video", "录屏历史", "视频"]
                    ),
                    CommandEntry(
                        id: "meow.recording.mobile",
                        title: L10n.cmdRecordingMobileTitle,
                        subtitle: L10n.cmdRecordingMobileSubtitle,
                        keywords: ["record", "iphone", "ipad", "mobile", "录制手机", "移动设备"]
                    ),
                ],
                at: min(2, entries.count)
            )
        }
        if settings.tts.enabled {
            entries.insert(
                contentsOf: [
                    CommandEntry(
                        id: "meow.tts.selection",
                        title: L10n.cmdTtsSelectionTitle,
                        subtitle: L10n.cmdTtsSelectionSubtitle,
                        keywords: ["speak", "read", "tts", "selection", "selected text",
                                   "朗读", "语音合成", "选中文本", "选择"]
                    ),
                    CommandEntry(
                        id: "meow.tts.clipboard",
                        title: L10n.cmdTtsClipboardTitle,
                        subtitle: L10n.cmdTtsClipboardSubtitle,
                        keywords: ["speak", "read", "tts", "clipboard", "voice",
                                   "朗读", "语音合成", "剪贴板", "文字转语音"]
                    ),
                ],
                at: min(2, entries.count)
            )
        }
        return entries
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

    func clearClipboardItems() {
        guard settings.clipboardHistoryEnabled else { return }
        clipboardStore.clearAll()
    }

    func copyClipboardItem(_ item: SearchItem) {
        guard settings.clipboardHistoryEnabled else { return }
        guard case let .clipboard(entry) = item else { return }
        clipboardStore.writeToPasteboard(entry)
    }

    func pinClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onPinClipboardImage?(image)
    }

    func recognizeClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onRecognizeClipboardImage?(image)
    }

    func translateClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onTranslateClipboardImage?(image)
    }

    func scanClipboardImageQRCode(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onScanClipboardImageQRCode?(image)
    }

    func editClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onEditClipboardImage?(image)
    }

    func openClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onOpenClipboardImage?(image)
    }

    func saveClipboardImage(_ item: SearchItem) {
        guard case let .clipboard(entry) = item,
              case let .image(image) = entry.content
        else { return }
        onSaveClipboardImage?(image)
    }

    func speakClipboardText(_ item: SearchItem) {
        guard settings.tts.enabled,
              case let .clipboard(entry) = item,
              case let .text(text) = entry.content
        else { return }
        onSpeakText?(text)
    }

    func speakLatestClipboardText() {
        guard settings.tts.enabled, let text = latestClipboardText() else { return }
        onSpeakText?(text)
    }

    func openAIChat(prompt: String?) {
        guard let prompt else {
            onOpenAIChat?(nil)
            return
        }
        onOpenAIChat?(AIChatInitialInput(text: prompt))
    }

    func openAIChat(prompt: String, imagePath: String) {
        onOpenAIChat?(AIChatInitialInput(text: prompt, imagePath: imagePath))
    }

    func updateKeystrokeOverlayPlacement(position: KeystrokeOverlayPosition, point: KeystrokeOverlayPoint?) {
        var updated = settings
        updated.keystrokeVisualizerOverlayPosition = position
        updated.keystrokeVisualizerOverlayPoint = point
        settings = updated
    }

    func updateLauncherHotkey(keyCode: UInt32, modifiers: UInt32) {
        var updated = settings
        updated.hotkeyKeyCode = keyCode
        updated.hotkeyModifiers = modifiers
        settings = updated
    }

    func updateTranslateHotkey(keyCode: UInt32, modifiers: UInt32) {
        var updated = settings
        updated.translateHotkeyKeyCode = keyCode
        updated.translateHotkeyModifiers = modifiers
        settings = updated
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
        case "meow.ai.chat":
            onOpenAIChat?(nil)
        case "meow.authenticator":
            onOpenAuthenticator?()
        case "meow.upload.clipboard":
            onUploadClipboard?()
        case "meow.health.start":
            onHealthCommand?(.start)
        case "meow.health.pause":
            onHealthCommand?(.pauseResume)
        case "meow.health.break":
            onHealthCommand?(.startBreak)
        case "meow.health.skip":
            onHealthCommand?(.skipBreak)
        case "meow.screenshot.region":
            onScreenshotCommand?(.captureRegion)
        case "meow.screenshot.edit":
            onScreenshotCommand?(.captureAndEdit)
        case "meow.screenshot.window":
            onScreenshotCommand?(.captureWindow)
        case "meow.screenshot.display":
            onScreenshotCommand?(.captureDisplay)
        case "meow.screenshot.history":
            onScreenshotCommand?(.openHistory)
        case "meow.screenshot.ocr.latest":
            if let image = latestClipboardImage() {
                onRecognizeClipboardImage?(image)
            }
        case "meow.screenshot.translate.latest":
            if let image = latestClipboardImage() {
                onTranslateClipboardImage?(image)
            }
        case "meow.screenshot.pin.latest":
            if let image = latestClipboardImage() {
                onPinClipboardImage?(image)
            }
        case "meow.recording.display":
            onRecordingCommand?(.recordDisplay)
        case "meow.recording.region":
            onRecordingCommand?(.recordRegion)
        case "meow.recording.window":
            onRecordingCommand?(.recordWindow)
        case "meow.recording.windows":
            onRecordingCommand?(.recordWindows)
        case "meow.recording.application":
            onRecordingCommand?(.recordApplication)
        case "meow.recording.audio":
            onRecordingCommand?(.recordSystemAudio)
        case "meow.recording.history":
            onRecordingCommand?(.openHistory)
        case "meow.recording.mobile":
            onRecordingCommand?(.recordMobileDevice)
        case "meow.tts.clipboard":
            speakLatestClipboardText()
        case "meow.tts.selection":
            onSpeakSelectedText?()
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

    private func latestClipboardImage() -> ImageClipboardContent? {
        for entry in clipboardStore.getEntries() {
            if case let .image(image) = entry.content {
                return image
            }
        }
        return nil
    }

    private func latestClipboardText() -> String? {
        for entry in clipboardStore.getEntries() {
            if case let .text(text) = entry.content,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }
        }
        return nil
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
