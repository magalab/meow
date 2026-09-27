import AppKit
import Foundation

@MainActor
final class StatusItemService {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var actionTargets: [BlockActionTarget] = []
    private var openItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var whiteboardItem: NSMenuItem?
    private var autoLaunchItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var recordingStatusItem: NSMenuItem?
    private var recordingPauseItem: NSMenuItem?
    private var recordingStopItem: NSMenuItem?
    private weak var dropView: StatusItemDropView?
    private var dateRefreshTimer: Timer?
    private var recordingActive = false

    private var currentStyle: DateIconStyle = .monthDay

    func setup(
        initialSettings: AppSettings,
        toggleLauncher: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        showCalendar: @escaping () -> Void,
        toggleAutoLaunch: @escaping () -> Void,
        toggleWhiteboard: @escaping () -> Void,
        pauseRecording: @escaping () -> Void,
        stopRecording: @escaping () -> Void,
        uploadDroppedFile: @escaping (URL) -> Void,
        quit: @escaping () -> Void
    ) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        currentStyle = initialSettings.dateIconStyle

        if let button = item.button {
            button.image = dateImage()
            button.toolTip = "Meow"
            scheduleDateRefresh(for: button)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let dropView = StatusItemDropView(
                isEnabled: initialSettings.fileHosting.s3.isEnabled,
                onDrop: uploadDroppedFile
            )
            dropView.frame = button.bounds
            dropView.autoresizingMask = [.width, .height]
            button.addSubview(dropView)
            self.dropView = dropView
        }

        // Keep the status menu focused on entry points and active controls.
        // Settings-only options belong in Preferences.
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

        let whiteboardItem = NSMenuItem(
            title: L10n.whiteboardMenuToggle,
            action: nil,
            keyEquivalent: ""
        )
        whiteboardItem.image = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: nil)
        let whiteboardTarget = BlockActionTarget { toggleWhiteboard() }
        actionTargets.append(whiteboardTarget)
        whiteboardItem.target = whiteboardTarget
        whiteboardItem.action = #selector(BlockActionTarget.invoke)
        whiteboardItem.isHidden = !initialSettings.whiteboard.enabled
        menu.addItem(whiteboardItem)
        self.whiteboardItem = whiteboardItem

        menu.addItem(.separator())

        let recordingStatusItem = NSMenuItem(
            title: L10n.recordingStatusIdle,
            action: nil,
            keyEquivalent: ""
        )
        recordingStatusItem.isEnabled = false
        recordingStatusItem.isHidden = true
        menu.addItem(recordingStatusItem)
        self.recordingStatusItem = recordingStatusItem

        let recordingPauseItem = NSMenuItem(
            title: L10n.recordingPause,
            action: nil,
            keyEquivalent: ""
        )
        let pauseTarget = BlockActionTarget { pauseRecording() }
        actionTargets.append(pauseTarget)
        recordingPauseItem.target = pauseTarget
        recordingPauseItem.action = #selector(BlockActionTarget.invoke)
        recordingPauseItem.isHidden = true
        menu.addItem(recordingPauseItem)
        self.recordingPauseItem = recordingPauseItem

        let recordingStopItem = NSMenuItem(
            title: L10n.recordingStop,
            action: nil,
            keyEquivalent: ""
        )
        let stopTarget = BlockActionTarget { stopRecording() }
        actionTargets.append(stopTarget)
        recordingStopItem.target = stopTarget
        recordingStopItem.action = #selector(BlockActionTarget.invoke)
        recordingStopItem.isHidden = true
        menu.addItem(recordingStopItem)
        self.recordingStopItem = recordingStopItem

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

        let autoLaunchItem = NSMenuItem(title: L10n.menuAutoLaunch, action: nil, keyEquivalent: "")
        let autoLaunchTarget = BlockActionTarget {
            toggleAutoLaunch()
        }
        actionTargets.append(autoLaunchTarget)
        autoLaunchItem.target = autoLaunchTarget
        autoLaunchItem.action = #selector(BlockActionTarget.invoke)
        menu.addItem(autoLaunchItem)
        self.autoLaunchItem = autoLaunchItem

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

        let clickTarget = BlockActionTarget { [weak self] in
            guard let self else { return }
            let event = NSApp.currentEvent
            let flags = event?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if event?.type == .rightMouseUp || flags.contains(.control) {
                if let statusMenu = self.statusMenu, let button = self.statusItem?.button {
                    statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
                }
            } else {
                showCalendar()
            }
        }
        actionTargets.append(clickTarget)
        item.button?.target = clickTarget
        item.button?.action = #selector(BlockActionTarget.invoke)

        statusMenu = menu
        statusItem = item
        updateToggleStates(initialSettings)
    }

    var statusItemButton: NSButton? {
        statusItem?.button
    }

    func setVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
    }

    func updateToggleStates(_ settings: AppSettings) {
        autoLaunchItem?.state = settings.autoLaunch ? .on : .off
        whiteboardItem?.isHidden = !settings.whiteboard.enabled
        dropView?.isDropEnabled = settings.fileHosting.s3.isEnabled
    }

    func updateL10n() {
        openItem?.title = L10n.menuOpen
        preferencesItem?.title = L10n.menuPreferences
        autoLaunchItem?.title = L10n.menuAutoLaunch
        whiteboardItem?.title = L10n.whiteboardMenuToggle
        quitItem?.title = L10n.quitMeow
    }

    func updateDateIconStyle(_ style: DateIconStyle) {
        currentStyle = style
        statusItem?.button?.image = dateImage()
    }

    /// Rebuilds the date icon and aligns its next scheduled update after a system wake.
    func refreshDateIcon() {
        guard let button = statusItem?.button else { return }
        if !recordingActive {
            button.image = dateImage()
        }
        scheduleDateRefresh(for: button)
    }

    func updateRecordingState(_ state: RecordingState, elapsed: TimeInterval) {
        let active = state.isActive
        recordingActive = active
        recordingStatusItem?.isHidden = !active
        recordingPauseItem?.isHidden = !active
        recordingStopItem?.isHidden = !active

        if active {
            let total = max(0, Int(elapsed))
            let time = String(format: "%02d:%02d", total / 60, total % 60)
            recordingStatusItem?.title = String(format: L10n.recordingStatusActive, time)
            if case .paused = state {
                recordingPauseItem?.title = L10n.recordingResume
            } else {
                recordingPauseItem?.title = L10n.recordingPause
            }
            statusItem?.button?.image = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: L10n.recordingStatusIdle
            )
            statusItem?.button?.contentTintColor = .systemRed
            statusItem?.button?.title = " \(time)"
        } else {
            statusItem?.button?.contentTintColor = nil
            statusItem?.button?.title = ""
            statusItem?.button?.image = dateImage()
        }
    }

    private func dateImage() -> NSImage {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        let weekday = cal.component(.weekday, from: now)

        let isChinese = LanguageManager.shared.isChinese

        let dayStr = "\(day)"

        switch currentStyle {
        case .outlinedDay:
            return renderBadge(lines: [dayStr], fill: false, cornerRadius: 3)
        case .roundedOutlineDay:
            return renderBadge(lines: [dayStr], fill: false, cornerRadius: 5)
        case .pawPrint:
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Meow")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            return image ?? pawPrintFallbackImage()
        case .dayOnly:
            return renderBadge(lines: [dayStr], fill: true, cornerRadius: 4)
        case .monthDay:
            let monthStr = shortMonth(month: month, isChinese: isChinese)
            return renderCompactTwoLineBadge(top: monthStr, bottom: dayStr)
        case .weekdayDay:
            let symbols = isChinese
                ? ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                : ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let weekdayStr = symbols[weekday]
            return renderCompactTwoLineBadge(top: weekdayStr, bottom: dayStr)
        case .lunarDate:
            let lunar = lunarDateStrings(for: now, isChinese: isChinese)
            return renderBadge(lines: lunar, fill: true, cornerRadius: 4)
        }
    }

    private func pawPrintFallbackImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18))
        image.isTemplate = true
        image.lockFocus()
        let text = "🐾" as NSString
        text.draw(at: NSPoint(x: 0, y: 0), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14),
        ])
        image.unlockFocus()
        return image
    }

    private func shortMonth(month: Int, isChinese: Bool) -> String {
        if isChinese {
            return "\(month)月"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        guard let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: month, day: 1)) else {
            return "\(month)"
        }
        return formatter.string(from: date)
    }

    private func renderBadge(lines: [String], fill: Bool, cornerRadius: CGFloat) -> NSImage {
        let fonts = lines.count == 1
            ? [NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)]
            : [
                NSFont.systemFont(ofSize: 8, weight: .bold),
                NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            ]
        let textSizes = zip(lines, fonts).map { text, font in
            (text as NSString).size(withAttributes: [.font: font])
        }
        let maxTextWidth = textSizes.map(\.width).max() ?? 14
        let width = max(CGFloat(lines.count == 1 ? 22 : 28), ceil(maxTextWidth) + 8)
        let height: CGFloat = lines.count == 1 ? 20 : 22
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = false

        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: width - 2, height: height - 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        let foreground = fill ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor.white

        if fill {
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
            path.fill()
        } else {
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        if lines.count == 1 {
            let text = lines[0] as NSString
            let size = textSizes[0]
            text.draw(
                at: NSPoint(x: (width - size.width) / 2, y: (height - size.height) / 2),
                withAttributes: [.font: fonts[0], .foregroundColor: foreground]
            )
        } else {
            let lineSpacing: CGFloat = -1
            let totalHeight = textSizes[0].height + textSizes[1].height + lineSpacing
            let topY = (height - totalHeight) / 2 + textSizes[1].height + lineSpacing
            let bottomY = (height - totalHeight) / 2
            for index in 0..<2 {
                let text = lines[index] as NSString
                let size = textSizes[index]
                let y = index == 0 ? topY : bottomY
                text.draw(
                    at: NSPoint(x: (width - size.width) / 2, y: y),
                    withAttributes: [.font: fonts[index], .foregroundColor: foreground]
                )
            }
        }
        image.unlockFocus()

        return image
    }

    private func renderCompactTwoLineBadge(top: String, bottom: String) -> NSImage {
        let topFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        let topSize = (top as NSString).size(withAttributes: [.font: topFont])
        let bottomSize = (bottom as NSString).size(withAttributes: [.font: bottomFont])
        let maxTextWidth = max(topSize.width, bottomSize.width)
        let width = max(CGFloat(28), ceil(maxTextWidth) + 8)
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = false

        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: width - 2, height: height - 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        path.fill()

        let foreground = NSColor(calibratedWhite: 0.08, alpha: 1)
        let topY = height - topSize.height + 0.2
        let bottomY: CGFloat = -0.7
        (top as NSString).draw(
            at: NSPoint(x: (width - topSize.width) / 2, y: topY),
            withAttributes: [.font: topFont, .foregroundColor: foreground]
        )
        (bottom as NSString).draw(
            at: NSPoint(x: (width - bottomSize.width) / 2, y: bottomY),
            withAttributes: [.font: bottomFont, .foregroundColor: foreground]
        )
        image.unlockFocus()

        return image
    }

    private func lunarDateStrings(for date: Date, isChinese: Bool) -> [String] {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh-Hans")
        let components = calendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1

        if isChinese {
            let monthNames = [
                1: "正月", 2: "二月", 3: "三月", 4: "四月", 5: "五月", 6: "六月",
                7: "七月", 8: "八月", 9: "九月", 10: "十月", 11: "冬月", 12: "腊月",
            ]
            let dayNames = [
                1: "初一", 2: "初二", 3: "初三", 4: "初四", 5: "初五",
                6: "初六", 7: "初七", 8: "初八", 9: "初九", 10: "初十",
                11: "十一", 12: "十二", 13: "十三", 14: "十四", 15: "十五",
                16: "十六", 17: "十七", 18: "十八", 19: "十九", 20: "二十",
                21: "廿一", 22: "廿二", 23: "廿三", 24: "廿四", 25: "廿五",
                26: "廿六", 27: "廿七", 28: "廿八", 29: "廿九", 30: "三十",
            ]
            let leapPrefix = components.isLeapMonth == true ? "闰" : ""
            return [
                "\(leapPrefix)\(monthNames[month] ?? "\(month)月")",
                dayNames[day] ?? "\(day)",
            ]
        }

        return ["Lunar", "\(day)"]
    }

    private func scheduleDateRefresh(for button: NSStatusBarButton) {
        dateRefreshTimer?.invalidate()
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return }
        let nextMidnight = cal.startOfDay(for: tomorrow)

        dateRefreshTimer = Timer(fire: nextMidnight, interval: 86400, repeats: true) { [weak self, weak button] _ in
            Task { @MainActor in
                guard let button, let self else { return }
                self.dateRefreshTimer?.invalidate()
                if !self.recordingActive {
                    button.image = self.dateImage()
                }
                self.scheduleDateRefresh(for: button)
            }
        }
        RunLoop.main.add(dateRefreshTimer!, forMode: .common)
    }
}

@MainActor
private final class BlockActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
