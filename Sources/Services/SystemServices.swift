import AppKit
import Carbon
import Foundation
import ServiceManagement

@MainActor
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

@MainActor
final class DockIconService {
    private var dayChangeObserver: NSObjectProtocol?
    private var style: DockIconStyle = .calendar

    func start(style: DockIconStyle = .calendar) {
        self.style = style
        refresh()
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        if let obs = dayChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            dayChangeObserver = nil
        }
    }

    func apply(style: DockIconStyle) {
        self.style = style
        refresh()
    }

    func refresh() {
        switch style {
        case .calendar:
            NSApp.applicationIconImage = Self.renderCalendarIcon()
        case .flat:
            NSApp.applicationIconImage = Self.renderFlatIcon()
        case .`default`:
            NSApp.applicationIconImage = nil
        }
    }

    static func renderCalendarIcon(size: CGFloat = 512) -> NSImage {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        let isChinese = LanguageManager.shared.currentLanguageCode.hasPrefix("zh")

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = size * 0.225
        let borderWidth: CGFloat = size * 0.04

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // Layer 1: Border (larger rounded rect filled with dark color)
            let borderPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(white: 0, alpha: 0.25).setFill()
            borderPath.fill()

            // Layer 2: Card content (slightly smaller rounded rect on top)
            let cardRect = rect.insetBy(dx: borderWidth, dy: borderWidth)
            let cardCorner = cornerRadius - borderWidth
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardCorner, yRadius: cardCorner)
            cardPath.addClip()

            // White card body
            let bgGrad = NSGradient(colors: [
                NSColor(white: 0.98, alpha: 1.0),
                NSColor(white: 0.94, alpha: 1.0),
            ])
            bgGrad?.draw(in: cardRect, angle: 90)

            // Red header
            let headerHeight: CGFloat = cardRect.height * 0.28
            let headerRect = NSRect(x: cardRect.minX, y: cardRect.maxY - headerHeight,
                                    width: cardRect.width, height: headerHeight)
            let headerGrad = NSGradient(colors: [
                NSColor(calibratedRed: 0.82, green: 0.15, blue: 0.15, alpha: 1.0),
                NSColor(calibratedRed: 0.92, green: 0.22, blue: 0.22, alpha: 1.0),
            ])
            headerGrad?.draw(in: headerRect, angle: 90)

            // Shadow below header
            let sepY = cardRect.maxY - headerHeight
            let shadowH: CGFloat = cardRect.width * 0.03
            NSGradient(colors: [
                NSColor(white: 0, alpha: 0.10),
                NSColor(white: 0, alpha: 0.0),
            ])?.draw(in: NSRect(x: cardRect.minX, y: sepY - shadowH,
                                 width: cardRect.width, height: shadowH), angle: 90)

            // Month label
            let monthStr = isChinese ? "\(month)月" : shortMonthENStatic(month: month).uppercased()
            let monthFont = NSFont.systemFont(ofSize: cardRect.width * 0.105, weight: .semibold)
            let monthSize = (monthStr as NSString).size(withAttributes: [.font: monthFont, .foregroundColor: NSColor.white])
            (monthStr as NSString).draw(
                at: NSPoint(x: cardRect.midX - monthSize.width / 2,
                            y: cardRect.maxY - headerHeight + (headerHeight - monthSize.height) / 2),
                withAttributes: [.font: monthFont, .foregroundColor: NSColor.white]
            )

            // Day number
            let dayStr = "\(day)"
            let dayFont = NSFont.systemFont(ofSize: cardRect.width * 0.36, weight: .ultraLight)
            let daySize = (dayStr as NSString).size(withAttributes: [.font: dayFont])
            let bodyH = cardRect.height - headerHeight
            let dayY = cardRect.minY + (bodyH - daySize.height) / 2 - bodyH * 0.02
            (dayStr as NSString).draw(
                at: NSPoint(x: cardRect.midX - daySize.width / 2, y: dayY),
                withAttributes: [.font: dayFont, .foregroundColor: NSColor(white: 0.08, alpha: 1.0)]
            )

            return true
        }
    }

    static func renderFlatIcon(size: CGFloat = 512) -> NSImage {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: now)
        let isChinese = LanguageManager.shared.currentLanguageCode.hasPrefix("zh")

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = size * 0.225
        let borderWidth: CGFloat = size * 0.04

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // Layer 1: Border
            let borderPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(white: 0, alpha: 0.30).setFill()
            borderPath.fill()

            // Layer 2: Card content
            let cardRect = rect.insetBy(dx: borderWidth, dy: borderWidth)
            let cardCorner = cornerRadius - borderWidth
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardCorner, yRadius: cardCorner)
            cardPath.addClip()

            // Gradient background
            NSGradient(colors: [
                NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.26, alpha: 1.0),
                NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.18, alpha: 1.0),
            ])?.draw(in: cardRect, angle: 90)

            // Inner shadow at top
            NSGradient(colors: [
                NSColor(white: 0, alpha: 0.18),
                NSColor(white: 0, alpha: 0.0),
            ])?.draw(in: NSRect(x: cardRect.minX, y: cardRect.maxY - cardRect.height * 0.18,
                                 width: cardRect.width, height: cardRect.height * 0.18), angle: 90)

            // Day number — centered with slight nudge down
            let dayStr = "\(day)"
            let dayFont = NSFont.systemFont(ofSize: cardRect.width * 0.44, weight: .medium)
            let daySize = (dayStr as NSString).size(withAttributes: [.font: dayFont])
            let dayY = cardRect.midY - daySize.height / 2 - cardRect.height * 0.02
            (dayStr as NSString).draw(
                at: NSPoint(x: cardRect.midX - daySize.width / 2, y: dayY),
                withAttributes: [.font: dayFont, .foregroundColor: NSColor.white]
            )

            // Weekday label near bottom
            let weekdaySymbols = isChinese
                ? ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                : ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let weekday = cal.component(.weekday, from: now)
            let weekdayStr = weekdaySymbols[weekday]
            let weekdayFont = NSFont.systemFont(ofSize: cardRect.width * 0.10, weight: .medium)
            let weekdaySize = (weekdayStr as NSString).size(withAttributes: [.font: weekdayFont])
            (weekdayStr as NSString).draw(
                at: NSPoint(x: cardRect.midX - weekdaySize.width / 2,
                            y: cardRect.minY + cardRect.height * 0.10),
                withAttributes: [.font: weekdayFont, .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
            )

            return true
        }
    }

    private static func shortMonthENStatic(month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        guard let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: month, day: 1)
        ) else {
            return "\(month)"
        }
        return formatter.string(from: date)
    }
}

@MainActor
final class StatusItemService {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var actionTargets: [BlockActionTarget] = []
    private var openItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var autoLaunchItem: NSMenuItem?
    private var dockIconItem: NSMenuItem?
    private var statusBarIconItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var recordingStatusItem: NSMenuItem?
    private var recordingPauseItem: NSMenuItem?
    private var recordingStopItem: NSMenuItem?
    private var recordingHistoryItem: NSMenuItem?
    private var dateRefreshTimer: Timer?
    private var recordingActive = false

    private var currentStyle: DateIconStyle = .monthDay
    private var iconStyleMenuItems: [NSMenuItem] = []
    private var iconStyleSubmenuItem: NSMenuItem?

    var onDateIconStyleChanged: ((DateIconStyle) -> Void)?

    func setup(
        initialSettings: AppSettings,
        toggleLauncher: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        showCalendar: @escaping () -> Void,
        toggleAutoLaunch: @escaping () -> Void,
        toggleDockIcon: @escaping () -> Void,
        toggleStatusBarIcon: @escaping () -> Void,
        pauseRecording: @escaping () -> Void,
        stopRecording: @escaping () -> Void,
        openRecordingHistory: @escaping () -> Void,
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

        let recordingHistoryItem = NSMenuItem(
            title: L10n.recordingHistoryTitle,
            action: nil,
            keyEquivalent: ""
        )
        let historyTarget = BlockActionTarget { openRecordingHistory() }
        actionTargets.append(historyTarget)
        recordingHistoryItem.target = historyTarget
        recordingHistoryItem.action = #selector(BlockActionTarget.invoke)
        recordingHistoryItem.isHidden = !initialSettings.recording.enabled
        menu.addItem(recordingHistoryItem)
        self.recordingHistoryItem = recordingHistoryItem

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

        let iconSubmenu = NSMenu()
        let iconSubmenuItem = NSMenuItem(title: L10n.menuIconStyle, action: nil, keyEquivalent: "")
        iconSubmenuItem.submenu = iconSubmenu
        menu.addItem(iconSubmenuItem)
        self.iconStyleSubmenuItem = iconSubmenuItem

        for style in DateIconStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: nil, keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = style == currentStyle ? .on : .off
            let target = BlockActionTarget { [weak self] in
                guard let self else { return }
                self.currentStyle = style
                self.statusItem?.button?.image = self.dateImage()
                self.updateIconStyleSubmenuState()
                self.onDateIconStyleChanged?(style)
            }
            actionTargets.append(target)
            item.target = target
            item.action = #selector(BlockActionTarget.invoke)
            iconSubmenu.addItem(item)
            iconStyleMenuItems.append(item)
        }

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
        dockIconItem?.state = settings.showDockIcon ? .on : .off
        statusBarIconItem?.state = settings.showStatusItem ? .on : .off
        recordingHistoryItem?.isHidden = !settings.recording.enabled
    }

    func updateL10n() {
        openItem?.title = L10n.menuOpen
        preferencesItem?.title = L10n.menuPreferences
        iconStyleSubmenuItem?.title = L10n.menuIconStyle
        autoLaunchItem?.title = L10n.menuAutoLaunch
        dockIconItem?.title = L10n.menuDock
        statusBarIconItem?.title = L10n.menuMenuBar
        quitItem?.title = L10n.quitMeow
        recordingHistoryItem?.title = L10n.recordingHistoryTitle
        for item in iconStyleMenuItems {
            if let rawValue = item.representedObject as? String,
               let style = DateIconStyle(rawValue: rawValue)
            {
                item.title = style.displayName
            }
        }
        updateIconStyleSubmenuState()
    }

    func updateDateIconStyle(_ style: DateIconStyle) {
        currentStyle = style
        statusItem?.button?.image = dateImage()
        updateIconStyleSubmenuState()
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

    private func updateIconStyleSubmenuState() {
        for item in iconStyleMenuItems {
            let rawValue = item.representedObject as? String
            item.state = rawValue == currentStyle.rawValue ? .on : .off
        }
    }

    private func dateImage() -> NSImage {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        let weekday = cal.component(.weekday, from: now)

        let isChinese = LanguageManager.shared.currentLanguageCode.hasPrefix("zh")

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

final class AppDiscoveryService {
    private let manager = FileManager.default

    func discoverApplications() -> [AppEntry] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
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

        // Some macOS builds expose Safari via system-managed symlink paths.
        // Ensure Safari is discoverable even when directory enumeration misses it.
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            let safariID = safariURL.path
            if !seen.contains(safariID) {
                seen.insert(safariID)
                entries.append(
                    AppEntry(
                        id: safariID,
                        name: "Safari",
                        bundleId: "com.apple.Safari",
                        url: safariURL
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

final class HotkeyService: @unchecked Sendable {
    enum RegistrationResult: Equatable {
        case registered
        case failed(OSStatus)

        var isRegistered: Bool {
            if case .registered = self { return true }
            return false
        }
    }

    private struct RegisteredHotkey {
        let keyCode: UInt32
        let modifiers: UInt32
        let ref: EventHotKeyRef
        let pressedAction: () -> Void
        let releasedAction: (() -> Void)?
    }

    private var hotKeys: [UInt32: RegisteredHotkey] = [:]
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        unregister()
    }

    /// Registers (or replaces) the launcher-toggle hotkey (id = 1).
    func registerToggleHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 1, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the translate hotkey (id = 2).
    func registerTranslateHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 2, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    /// Registers (or replaces) the hold-to-record speech hotkey (id = 3).
    func registerSpeechHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        pressedAction: @escaping () -> Void,
        releasedAction: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(
            id: 3,
            keyCode: keyCode,
            modifiers: modifiers,
            pressedAction: pressedAction,
            releasedAction: releasedAction
        )
    }

    func unregisterSpeechHotkey() {
        unregisterHotkey(id: 3)
    }

    func registerScreenshotRegionHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 4, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotWindowHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 5, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotEditHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 7, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerScreenshotDisplayHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 6, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingDisplayHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 8, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingRegionHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 9, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingWindowHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 10, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingPauseHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 11, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingStopHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 12, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func unregisterRecordingHotkeys() {
        for id: UInt32 in 8...14 {
            unregisterHotkey(id: id)
        }
    }

    func registerRecordingFrameHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 13, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func registerRecordingMagnifierHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> RegistrationResult {
        registerHotkey(id: 14, keyCode: keyCode, modifiers: modifiers, pressedAction: action)
    }

    func unregisterScreenshotHotkeys() {
        unregisterHotkey(id: 4)
        unregisterHotkey(id: 5)
        unregisterHotkey(id: 6)
        unregisterHotkey(id: 7)
    }

    func unregister() {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey.ref) }
        hotKeys.removeAll()
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

        guard status == noErr else { return noErr }
        let callbackID = hotKeyID.id
        let eventKind = GetEventKind(event)
        DispatchQueue.main.async { [weak self] in
            guard let hotkey = self?.hotKeys[callbackID] else { return }
            if eventKind == UInt32(kEventHotKeyReleased) {
                hotkey.releasedAction?()
            } else {
                hotkey.pressedAction()
            }
        }
        return noErr
    }

    // MARK: - Private

    private func registerHotkey(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        pressedAction: @escaping () -> Void,
        releasedAction: (() -> Void)? = nil
    ) -> RegistrationResult {
        if eventHandlerRef == nil {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotkeyHandler,
                eventTypes.count,
                &eventTypes,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )
            guard status == noErr else {
                NSLog("[Meow] Failed to install hotkey event handler: \(status)")
                return .failed(status)
            }
        }

        if let existing = hotKeys[id],
           existing.keyCode == keyCode,
           existing.modifiers == modifiers
        {
            hotKeys[id] = RegisteredHotkey(
                keyCode: keyCode,
                modifiers: modifiers,
                ref: existing.ref,
                pressedAction: pressedAction,
                releasedAction: releasedAction
            )
            return .registered
        }

        let previous = hotKeys[id]
        if let previous {
            UnregisterEventHotKey(previous.ref)
            hotKeys[id] = nil
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("MEOW"), id: id)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr, let ref = hotKeyRef {
            hotKeys[id] = RegisteredHotkey(
                keyCode: keyCode,
                modifiers: modifiers,
                ref: ref,
                pressedAction: pressedAction,
                releasedAction: releasedAction
            )
            return .registered
        }

        if let previous {
            restorePreviousHotkey(previous, id: id)
        }

        NSLog("[Meow] Failed to register hotkey id=\(id): \(registerStatus)")
        return .failed(registerStatus)
    }

    private func restorePreviousHotkey(_ previous: RegisteredHotkey, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("MEOW"), id: id)
        var restoredRef: EventHotKeyRef?
        let restoreStatus = RegisterEventHotKey(
            previous.keyCode,
            previous.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &restoredRef
        )

        if restoreStatus == noErr, let restoredRef {
            hotKeys[id] = RegisteredHotkey(
                keyCode: previous.keyCode,
                modifiers: previous.modifiers,
                ref: restoredRef,
                pressedAction: previous.pressedAction,
                releasedAction: previous.releasedAction
            )
        } else {
            NSLog("[Meow] Failed to restore previous hotkey id=\(id): \(restoreStatus)")
        }
    }

    private func unregisterHotkey(id: UInt32) {
        guard let hotkey = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(hotkey.ref)
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
