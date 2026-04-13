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

private struct LaunchStat: Codable {
    var launches: Int
    var lastLaunchedAt: TimeInterval
}

final class LaunchHistoryStore {
    private enum Key {
        static let launchHistory = "meow.launch-history"
    }

    private let defaults = UserDefaults.standard

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
        guard let data = defaults.data(forKey: Key.launchHistory),
              let decoded = try? JSONDecoder().decode([String: LaunchStat].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func saveMap(_ map: [String: LaunchStat]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Key.launchHistory)
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
