import SwiftUI
import AppKit

// MARK: - Full Calendar Popover View

struct CalendarPopoverView: View {
    let theme: AppTheme
    @State private var currentYear: Int
    @State private var currentMonth: Int
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let calendarService = CalendarService.shared

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    init(theme: AppTheme) {
        self.theme = theme
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        _currentYear = State(initialValue: cal.component(.year, from: now))
        _currentMonth = State(initialValue: cal.component(.month, from: now))
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView
            calendarGrid
        }
        .padding(16)
        .frame(width: 320)
        .animation(.snappy(duration: 0.25), value: currentYear)
        .animation(.snappy(duration: 0.25), value: currentMonth)
        .id(lang.refreshToken)
    }

    private enum MonthPosition { case past, current, future }

    private var monthPosition: MonthPosition {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let curYear = cal.component(.year, from: now)
        let curMonth = cal.component(.month, from: now)
        if currentYear == curYear, currentMonth == curMonth { return .current }
        if currentYear < curYear || (currentYear == curYear && currentMonth < curMonth) { return .past }
        return .future
    }

    private var pawColor: Color {
        switch monthPosition {
        case .past: return .secondary
        case .current: return palette.preferencesAccent
        case .future: return palette.preferencesAccent.opacity(0.5)
        }
    }

    private var headerView: some View {
        HStack(spacing: 4) {
            Text(calendarService.monthYearString(year: currentYear, month: currentMonth))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer()

            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.snappy(duration: 0.35)) {
                    jumpToToday()
                }
            } label: {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(pawColor)
            }
            .buttonStyle(.plain)

            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
    }

    private var calendarGrid: some View {
        let days = calendarService.monthDays(year: currentYear, month: currentMonth)
        let symbols = calendarService.weekdaySymbols

        return VStack(spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                }

                ForEach(days) { dayInfo in
                    dayCell(dayInfo)
                }
            }
        }
    }

    private func dayCell(_ info: MonthDayInfo) -> some View {
        VStack(spacing: 1) {
            Text("\(info.day)")
                .font(.system(size: 13, weight: info.isToday ? .bold : .regular, design: .rounded))
                .foregroundStyle(dayColor(info))

            Text(info.holiday ?? info.solarTerm ?? info.lunarDay)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(daySubtitleColor(info))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(info.isToday ? palette.selectionBackground : Color.clear)
        )
    }

    private func dayColor(_ info: MonthDayInfo) -> Color {
        if info.isToday { return palette.preferencesAccent }
        if !info.isCurrentMonth { return .secondary.opacity(0.4) }
        if info.isWeekend { return .secondary }
        return .primary
    }

    private func daySubtitleColor(_ info: MonthDayInfo) -> Color {
        if info.solarTerm != nil { return palette.preferencesAccent.opacity(0.7) }
        if info.holiday != nil { return palette.preferencesAccent.opacity(0.7) }
        if !info.isCurrentMonth { return .secondary.opacity(0.3) }
        return .secondary.opacity(0.6)
    }

    private func jumpToToday() {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        currentYear = cal.component(.year, from: now)
        currentMonth = cal.component(.month, from: now)
    }

    private func moveMonth(_ delta: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            currentMonth += delta
            if currentMonth > 12 {
                currentMonth = 1
                currentYear += 1
            } else if currentMonth < 1 {
                currentMonth = 12
                currentYear -= 1
            }
        }
    }
}

// MARK: - Mini Calendar Launcher Section

struct MiniCalendarSectionView: View {
    let theme: AppTheme
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private let calendarService = CalendarService.shared

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let days = calendarService.monthDays(year: year, month: month)
        let symbols = calendarService.weekdaySymbols

        VStack(spacing: 6) {
            HStack {
                Text(calendarService.monthYearString(year: year, month: month))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(calendarService.todayDateString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 2) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(height: 14)
                }

                ForEach(days.prefix(35)) { info in
                    miniDayCell(info)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 2)
        .id(lang.refreshToken)
    }

    private func miniDayCell(_ info: MonthDayInfo) -> some View {
        let showLunar = info.isCurrentMonth && (LanguageManager.shared.currentLanguageCode.hasPrefix("zh") ? info.lunarDay != "初一" : info.lunarDay != "1st") && info.solarTerm == nil
        let label = info.holiday ?? info.solarTerm ?? (showLunar ? info.lunarDay : "")

        return Text("\(info.day)")
            .font(.system(size: 11, weight: info.isToday ? .bold : .regular, design: .rounded))
            .foregroundStyle(miniDayColor(info))
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(
                ZStack {
                    if info.isToday {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(palette.selectionBackground)
                    }
                }
            )
            .overlay(
                alignment: .bottom,
                content: {
                    if !label.isEmpty {
                        Text(label)
                            .font(.system(size: 6, weight: .medium))
                            .foregroundStyle(miniSubColor(info))
                            .lineLimit(1)
                            .offset(y: -1)
                    }
                }
            )
    }

    private func miniDayColor(_ info: MonthDayInfo) -> Color {
        if info.isToday { return palette.preferencesAccent }
        if !info.isCurrentMonth { return .secondary.opacity(0.35) }
        if info.isWeekend { return .secondary }
        return .primary
    }

    private func miniSubColor(_ info: MonthDayInfo) -> Color {
        if info.solarTerm != nil || info.holiday != nil { return palette.preferencesAccent.opacity(0.6) }
        return .secondary.opacity(0.5)
    }
}

// MARK: - Launcher Empty State Calendar Section

struct LauncherCalendarSection: View {
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(CalendarService.shared.todayDateString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            MiniCalendarSectionView(theme: theme)
        }
    }
}
