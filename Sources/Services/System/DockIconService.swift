import AppKit
import Foundation

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
        let isChinese = LanguageManager.shared.isChinese

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
        let isChinese = LanguageManager.shared.isChinese

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
