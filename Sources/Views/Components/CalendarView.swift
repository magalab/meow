import SwiftUI
import AppKit

// MARK: - Full Calendar Popover View

struct CalendarPopoverView: View {
    let theme: AppTheme
    let onContentSizeChanged: (NSSize) -> Void
    @State private var currentYear: Int
    @State private var currentMonth: Int
    @State private var selectedDay: MonthDayInfo?
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let calendarService = CalendarService.shared

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    init(theme: AppTheme, onContentSizeChanged: @escaping (NSSize) -> Void = { _ in }) {
        self.theme = theme
        self.onContentSizeChanged = onContentSizeChanged
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        _currentYear = State(initialValue: cal.component(.year, from: now))
        _currentMonth = State(initialValue: cal.component(.month, from: now))
    }

    private var daysInCurrentGrid: [MonthDayInfo] {
        calendarService.monthDays(year: currentYear, month: currentMonth)
    }

    private var currentGridRows: Int {
        max(5, daysInCurrentGrid.count / 7)
    }

    private var contentHeight: CGFloat {
        currentGridRows > 5 ? 318 : 282
    }

    private var contentSize: NSSize {
        NSSize(width: selectedDay == nil ? 320 : 660, height: contentHeight + 32)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 16) {
                headerView
                calendarGrid
            }
            .frame(width: 288)

            if let selectedDay {
                Divider()
                    .padding(.horizontal, 14)

                CalendarDayDetailPanel(
                    dayInfo: selectedDay,
                    theme: theme,
                    onBack: {
                        withAnimation(.snappy(duration: 0.2)) {
                            self.selectedDay = nil
                        }
                    }
                )
                .frame(width: 300, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(width: selectedDay == nil ? 320 : 660, height: contentHeight, alignment: .topLeading)
        .animation(.snappy(duration: 0.25), value: currentYear)
        .animation(.snappy(duration: 0.25), value: currentMonth)
        .animation(.snappy(duration: 0.22), value: selectedDay?.id)
        .onAppear {
            onContentSizeChanged(contentSize)
        }
        .onChange(of: selectedDay?.id) { _, _ in
            onContentSizeChanged(contentSize)
        }
        .onChange(of: currentYear) { _, _ in
            onContentSizeChanged(contentSize)
        }
        .onChange(of: currentMonth) { _, _ in
            onContentSizeChanged(contentSize)
        }
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
        let days = daysInCurrentGrid
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
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedDay = info
            }
        } label: {
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
                    .fill(dayBackground(info))
            )
        }
        .buttonStyle(.plain)
    }

    private func dayColor(_ info: MonthDayInfo) -> Color {
        if selectedDay?.id == info.id { return .primary }
        if info.isToday { return palette.preferencesAccent }
        if !info.isCurrentMonth { return .secondary.opacity(0.4) }
        if info.isWeekend { return .secondary }
        return .primary
    }

    private func dayBackground(_ info: MonthDayInfo) -> Color {
        if selectedDay?.id == info.id { return palette.selectionBackground.opacity(0.9) }
        if info.isToday { return palette.selectionBackground }
        return .clear
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
            selectedDay = nil
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

private struct CalendarDayDetailPanel: View {
    let dayInfo: MonthDayInfo
    let theme: AppTheme
    let onBack: () -> Void
    @StateObject private var eventService = CalendarEventService()
    @Environment(\.colorScheme) private var colorScheme
    private let calendarService = CalendarService.shared

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 10) {
                    Text(calendarService.detailDateString(for: dayInfo.date))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(calendarService.detailLunarString(for: dayInfo.date))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Color.clear
                    .frame(width: 17, height: 17)
            }

            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.calendarEventsTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                eventContent
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.trailing, 2)
        .background(Color.clear)
        .onAppear {
            eventService.loadEvents(on: dayInfo.date)
        }
        .onChange(of: dayInfo.id) { _, _ in
            eventService.loadEvents(on: dayInfo.date)
        }
    }

    @ViewBuilder
    private var eventContent: some View {
        switch eventService.state {
        case .idle, .loading:
            CalendarEventStatusText(text: L10n.calendarEventsLoading)
        case let .loaded(events):
            if events.isEmpty {
                CalendarEventStatusText(text: L10n.calendarEventsEmpty)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            CalendarEventRow(event: event)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 150)
            }
        case .denied:
            CalendarEventStatusText(text: L10n.calendarEventsDenied)
        case .restricted:
            CalendarEventStatusText(text: L10n.calendarEventsRestricted)
        case .failed:
            CalendarEventStatusText(text: L10n.calendarEventsError)
        }
    }
}

private struct CalendarEventStatusText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEventInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(nsColor: event.calendarColor))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(event.timeText)
                    Text(event.calendarTitle)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}
