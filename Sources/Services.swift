import AppKit
import Carbon
import Foundation
import ServiceManagement

final class SettingsStore {
    private enum Key {
        static let settings = "meow.settings"
    }

    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func save(_ settings: AppSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        defaults.set(encoded, forKey: Key.settings)
    }
}

final class ClipboardImageCache {
    static let shared = ClipboardImageCache()

    private let cacheDir: URL
    private let maxImageDimension: CGFloat = 2048

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("Meow/Clipboard", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func saveImage(_ image: NSImage, sourceName: String = "Screenshot") -> ImageClipboardContent? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Generate thumbnail
        let thumbnailSize = NSSize(width: 100, height: 100)
        let thumbnail = image.resized(to: thumbnailSize)

        // Add timestamp to prevent overwriting same-name screenshots
        let timestamp = Int(Date().timeIntervalSince1970)
        let cleanName = sourceName.replacingOccurrences(of: "/", with: "_")
        let originalPath = cacheDir.appendingPathComponent("\(cleanName)_\(timestamp)")
        let thumbnailPath = cacheDir.appendingPathComponent("\(cleanName)_\(timestamp)_thumb.png")

        // Save thumbnail
        guard let thumbnailData = thumbnail.pngData() else { return nil }
        try? thumbnailData.write(to: thumbnailPath)

        // Save original if not too large, as PNG (screenshots don't have original format)
        if width <= Int(maxImageDimension) && height <= Int(maxImageDimension) {
            if let originalData = image.pngData() {
                try? originalData.write(to: originalPath)
            }
        }

        return ImageClipboardContent(
            thumbnailPath: thumbnailPath.path,
            originalPath: width <= Int(maxImageDimension) && height <= Int(maxImageDimension) ? originalPath.path : nil,
            sourceName: sourceName,
            width: width,
            height: height
        )
    }

    /// Saves image preserving original file format
    func saveImageFromFile(data: Data, sourceName: String, image: NSImage) -> ImageClipboardContent? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Generate thumbnail (always PNG for thumbnails)
        let thumbnailSize = NSSize(width: 100, height: 100)
        let thumbnail = image.resized(to: thumbnailSize)

        // Use source name directly, clean invalid characters
        let cleanName = sourceName.replacingOccurrences(of: "/", with: "_")
        let originalPath = cacheDir.appendingPathComponent(cleanName)
        let thumbnailPath = cacheDir.appendingPathComponent("\(cleanName)_thumb.png")

        // Save thumbnail
        if let thumbnailData = thumbnail.pngData() {
            try? thumbnailData.write(to: thumbnailPath)
        }

        // Save original with correct format
        if width <= Int(maxImageDimension) && height <= Int(maxImageDimension) {
            try? data.write(to: originalPath)
        }

        return ImageClipboardContent(
            thumbnailPath: thumbnailPath.path,
            originalPath: width <= Int(maxImageDimension) && height <= Int(maxImageDimension) ? originalPath.path : nil,
            sourceName: sourceName,
            width: width,
            height: height
        )
    }

    func loadImage(from path: String) -> NSImage? {
        return NSImage(contentsOfFile: path)
    }

    func cleanupOldFiles() {
        // Clean up orphaned files periodically
        let contents = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        // Keep recent 100 files
        let sorted = contents.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }

        for url in sorted.dropFirst(100) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    func resized(to newSize: NSSize) -> NSImage {
        let aspectRatio = size.width / size.height
        var targetSize = newSize

        if size.width > size.height {
            targetSize.height = newSize.width / aspectRatio
        } else {
            targetSize.width = newSize.height * aspectRatio
        }

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

final class ClipboardStore {
    private static let maxEntries = 50
    private static let maxTextLength = 100_000

    private var entries: [ClipboardEntry] = []
    private var lastChangeCount: Int = 0
    private var monitorTimer: Timer?
    private var onChange: (() -> Void)?

    func startMonitoring(onChange: @escaping () -> Void) {
        stopMonitoring()
        self.onChange = onChange
        lastChangeCount = NSPasteboard.general.changeCount

        // Clean up old cache files on launch
        ClipboardImageCache.shared.cleanupOldFiles()

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func getEntries() -> [ClipboardEntry] {
        return entries
    }

    /// Tries to read an image from the pasteboard using multiple format checks.
    private func getImageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        // Try TIFF data
        if let data = pasteboard.data(forType: .tiff),
           let image = NSImage(data: data) {
            return image
        }

        // Try PNG data
        if let data = pasteboard.data(forType: .png),
           let image = NSImage(data: data) {
            return image
        }

        // Try reading as file URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            let image = NSImage(contentsOf: url)
            if image != nil {
                return image
            }
        }

        // Try reading directly as NSImage from pasteboard
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        return nil
    }

    func delete(_ entry: ClipboardEntry) {
        // Clean up disk cache for image/audio entries
        if case .image(let imageContent) = entry.content {
            try? FileManager.default.removeItem(atPath: imageContent.thumbnailPath)
            if let originalPath = imageContent.originalPath {
                try? FileManager.default.removeItem(atPath: originalPath)
            }
        } else if case .audio(let audioContent) = entry.content {
            try? FileManager.default.removeItem(atPath: audioContent.cachePath)
        }
        entries.removeAll { $0.id == entry.id }
        onChange?()
    }

    func writeToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)

        case .url(let url):
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.setString(url.absoluteString, forType: .URL)

        case .file(let fileContent):
            pasteboard.writeObjects([fileContent.url as NSURL])

        case .image(let imageContent):
            // Write image as TIFF data (most apps support this)
            if let originalPath = imageContent.originalPath,
               let image = NSImage(contentsOfFile: originalPath),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
                // Also write file URL for apps that prefer file promises
                pasteboard.writeObjects([URL(fileURLWithPath: originalPath) as NSURL])
            } else if let image = NSImage(contentsOfFile: imageContent.thumbnailPath),
                      let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }

        case .audio(let audioContent):
            let url = URL(fileURLWithPath: audioContent.cachePath)
            pasteboard.writeObjects([url as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for file URL first (from Finder file copy)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {

            // Check if it's a URL (web URL)
            if firstURL.scheme == "http" || firstURL.scheme == "https" {
                let entry = ClipboardEntry(
                    id: UUID().uuidString,
                    content: .url(firstURL),
                    copiedAt: Date()
                )
                addEntry(entry)
                return
            }

            // It's a file - check if it's an image by extension first
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "ico"]
            let ext = firstURL.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                // Read original file data directly to preserve format
                if let fileData = try? Data(contentsOf: firstURL),
                   let image = NSImage(contentsOf: firstURL) {
                    if let imageContent = ClipboardImageCache.shared.saveImageFromFile(
                        data: fileData,
                        sourceName: firstURL.lastPathComponent,
                        image: image
                    ) {
                        let entry = ClipboardEntry(
                            id: UUID().uuidString,
                            content: .image(imageContent),
                            copiedAt: Date()
                        )
                        addEntry(entry)
                        return
                    }
                }
            }

            // Not an image file, store as regular file
            let fileContent = FileClipboardContent(url: firstURL, name: firstURL.lastPathComponent)
            let entry = ClipboardEntry(
                id: UUID().uuidString,
                content: .file(fileContent),
                copiedAt: Date()
            )
            addEntry(entry)
            return
        }

        // Try to read files via pasteboardItems (handles some file promise cases)
        if let items = pasteboard.pasteboardItems {
            for item in items {
                let urlTypes = ["public.file-url"]
                for typeString in urlTypes {
                    let type = NSPasteboard.PasteboardType(typeString)
                    guard let data = item.data(forType: type),
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) else {
                        continue
                    }

                    let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "ico"]
                    let ext = url.pathExtension.lowercased()
                    if imageExtensions.contains(ext),
                       let fileData = try? Data(contentsOf: url),
                       let image = NSImage(contentsOf: url) {
                        if let imageContent = ClipboardImageCache.shared.saveImageFromFile(
                            data: fileData,
                            sourceName: url.lastPathComponent,
                            image: image
                        ) {
                            let entry = ClipboardEntry(
                                id: UUID().uuidString,
                                content: .image(imageContent),
                                copiedAt: Date()
                            )
                            addEntry(entry)
                            return
                        }
                    }
                    let fileContent = FileClipboardContent(url: url, name: url.lastPathComponent)
                    let entry = ClipboardEntry(
                        id: UUID().uuidString,
                        content: .file(fileContent),
                        copiedAt: Date()
                    )
                    addEntry(entry)
                    return
                }
            }
        }

        // Check for image data (TIFF, PNG) - this catches screenshots and app-copied images
        if let image = getImageFromPasteboard(pasteboard) {
            if let imageContent = ClipboardImageCache.shared.saveImage(image) {
                let entry = ClipboardEntry(
                    id: UUID().uuidString,
                    content: .image(imageContent),
                    copiedAt: Date()
                )
                addEntry(entry)
            }
            return
        }

        // Check for text
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Avoid recording our own writes
            if let last = entries.first,
               case .text(let lastText) = last.content,
               lastText == trimmed {
                return
            }

            let content = trimmed.count > Self.maxTextLength
                ? String(trimmed.prefix(Self.maxTextLength))
                : trimmed

            let entry = ClipboardEntry(
                id: UUID().uuidString,
                content: .text(content),
                copiedAt: Date()
            )
            addEntry(entry)
        }
    }

    private func addEntry(_ entry: ClipboardEntry) {
        // Remove duplicate if same content exists
        entries.removeAll { $0.content == entry.content }

        entries.insert(entry, at: 0)

        if entries.count > Self.maxEntries {
            let removed = entries.removeLast()
            // Clean up removed entry's disk cache
            if case .image(let imageContent) = removed.content {
                try? FileManager.default.removeItem(atPath: imageContent.thumbnailPath)
                if let originalPath = imageContent.originalPath {
                    try? FileManager.default.removeItem(atPath: originalPath)
                }
            }
        }

        onChange?()
    }
}

private struct LaunchStat: Codable {
    var launches: Int
    var lastLaunchedAt: TimeInterval
}

final class LaunchHistoryStore {
    private enum Key {
        static let launchHistory = "meow.launch-history"
    }
    
    /// Maximum number of launch history entries to keep in memory
    private static let maxHistoryEntries = 500

    private let defaults = UserDefaults.standard
    private var cachedMap: [String: LaunchStat]?

    func recordLaunch(id: String) {
        var map = loadMap()
        var stat = map[id] ?? LaunchStat(launches: 0, lastLaunchedAt: 0)
        stat.launches += 1
        stat.lastLaunchedAt = Date().timeIntervalSince1970
        map[id] = stat
        saveMap(map)
    }

    func score(for id: String) -> Int {
        let map = loadMap()
        guard let stat = map[id] else { return 0 }

        let now = Date().timeIntervalSince1970
        let age = max(0, now - stat.lastLaunchedAt)

        let recencyBoost: Int
        if age < 24 * 3600 {
            recencyBoost = 12
        } else if age < 7 * 24 * 3600 {
            recencyBoost = 8
        } else if age < 30 * 24 * 3600 {
            recencyBoost = 4
        } else {
            recencyBoost = 1
        }

        let frequencyBoost = min(stat.launches, 20)
        return recencyBoost + frequencyBoost
    }

    private func loadMap() -> [String: LaunchStat] {
        if let cachedMap {
            return cachedMap
        }

        guard let data = defaults.data(forKey: Key.launchHistory),
              let decoded = try? JSONDecoder().decode([String: LaunchStat].self, from: data)
        else {
            cachedMap = [:]
            return [:]
        }
        cachedMap = decoded
        return decoded
    }

    private func saveMap(_ map: [String: LaunchStat]) {
        // Prune oldest entries if over limit to prevent unbounded growth
        var prunedMap = map
        if prunedMap.count > Self.maxHistoryEntries {
            let sortedByRecency = prunedMap.sorted {
                ($0.value.lastLaunchedAt, $0.value.launches) > 
                ($1.value.lastLaunchedAt, $1.value.launches)
            }
            let kept = Array(sortedByRecency.prefix(Self.maxHistoryEntries))
            prunedMap = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        
        guard let data = try? JSONEncoder().encode(prunedMap) else { return }
        defaults.set(data, forKey: Key.launchHistory)
        cachedMap = prunedMap
    }
}

final class DockService {
    func apply(showDockIcon: Bool) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        if showDockIcon {
            _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

final class StatusItemService {
    private var statusItem: NSStatusItem?
    private var actionTargets: [BlockActionTarget] = []
    private var openItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var autoLaunchItem: NSMenuItem?
    private var dockIconItem: NSMenuItem?
    private var statusBarIconItem: NSMenuItem?
    private var quitItem: NSMenuItem?

    func setup(
        initialSettings: AppSettings,
        toggleLauncher: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        toggleAutoLaunch: @escaping () -> Void,
        toggleDockIcon: @escaping () -> Void,
        toggleStatusBarIcon: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Meow")
            button.toolTip = "Meow"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: L10n.menuOpen, action: nil, keyEquivalent: "")
        let openTarget = BlockActionTarget {
            toggleLauncher()
        }
        actionTargets.append(openTarget)
        openItem.target = openTarget
        openItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(openItem)
        self.openItem = openItem

        let preferencesItem = NSMenuItem(title: L10n.menuPreferences, action: nil, keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = [.command]
        let preferencesTarget = BlockActionTarget {
            openPreferences()
        }
        actionTargets.append(preferencesTarget)
        preferencesItem.target = preferencesTarget
        preferencesItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(preferencesItem)
        self.preferencesItem = preferencesItem

        menu.addItem(.separator())

        let autoLaunchItem = NSMenuItem(title: L10n.menuAutoLaunch, action: nil, keyEquivalent: "")
        let autoLaunchTarget = BlockActionTarget {
            toggleAutoLaunch()
        }
        actionTargets.append(autoLaunchTarget)
        autoLaunchItem.target = autoLaunchTarget
        autoLaunchItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(autoLaunchItem)
        self.autoLaunchItem = autoLaunchItem

        let dockIconItem = NSMenuItem(title: L10n.menuDock, action: nil, keyEquivalent: "")
        let dockIconTarget = BlockActionTarget {
            toggleDockIcon()
        }
        actionTargets.append(dockIconTarget)
        dockIconItem.target = dockIconTarget
        dockIconItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(dockIconItem)
        self.dockIconItem = dockIconItem

        let statusBarIconItem = NSMenuItem(title: L10n.menuMenuBar, action: nil, keyEquivalent: "")
        let statusBarIconTarget = BlockActionTarget {
            toggleStatusBarIcon()
        }
        actionTargets.append(statusBarIconTarget)
        statusBarIconItem.target = statusBarIconTarget
        statusBarIconItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(statusBarIconItem)
        self.statusBarIconItem = statusBarIconItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitMeow, action: nil, keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        let quitTarget = BlockActionTarget {
            quit()
        }
        actionTargets.append(quitTarget)
        quitItem.target = quitTarget
        quitItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(quitItem)
        self.quitItem = quitItem

        item.menu = menu
        statusItem = item
        updateToggleStates(initialSettings)
    }

    func setVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
    }

    func updateToggleStates(_ settings: AppSettings) {
        autoLaunchItem?.state = settings.autoLaunch ? .on : .off
        dockIconItem?.state = settings.showDockIcon ? .on : .off
        statusBarIconItem?.state = settings.showStatusItem ? .on : .off
    }

    func updateL10n() {
        openItem?.title = L10n.menuOpen
        preferencesItem?.title = L10n.menuPreferences
        autoLaunchItem?.title = L10n.menuAutoLaunch
        dockIconItem?.title = L10n.menuDock
        statusBarIconItem?.title = L10n.menuMenuBar
        quitItem?.title = L10n.quitMeow
    }
}

private final class BlockActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

final class AppDiscoveryService {
    private let manager = FileManager.default

    func discoverApplications() -> [AppEntry] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var seen = Set<String>()
        var entries: [AppEntry] = []

        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                let id = url.path
                guard !seen.contains(id) else { continue }
                seen.insert(id)

                let name = url.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                if lower.contains("appintents") || lower.contains("widget") || lower.contains("extension") {
                    continue
                }

                let bundle = Bundle(url: url)
                let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? name

                entries.append(
                    AppEntry(
                        id: id,
                        name: displayName,
                        bundleId: bundle?.bundleIdentifier,
                        url: url
                    )
                )
            }
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

final class AutoLaunchService {
    func apply(enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("[Meow] Failed to update launch-at-login: \(error.localizedDescription)")
        }

        return isEnabled
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}

final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onToggle: (() -> Void)?

    deinit {
        unregister()
    }

    func registerToggleHotkey(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        onToggle = action

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotkeyHandler,
                1,
                &eventType,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )

            guard status == noErr else {
                NSLog("[Meow] Failed to install hotkey event handler: \(status)")
                return
            }
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("MEOW"), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            NSLog("[Meow] Failed to register hotkey: \(registerStatus)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotkey(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.id == 1 else { return noErr }
        DispatchQueue.main.async { [weak self] in
            self?.onToggle?()
        }
        return noErr
    }
}

private let hotkeyHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else { return noErr }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    return service.handleHotkey(eventRef)
}

private func fourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for scalar in string.uppercased().unicodeScalars.prefix(4) {
        result = (result << 8) + scalar.value
    }
    return result
}
