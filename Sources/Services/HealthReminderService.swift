import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
final class HealthReminderStore {
    private enum Key {
        static let records = "meow.health.reminder.records"
    }

    private let defaults = UserDefaults.standard
    private let maxRecords = 90

    func record(for date: String = HealthReminderStore.todayString()) -> HealthReminderDayRecord {
        records()[date] ?? HealthReminderDayRecord(date: date, completedBreaks: 0, skippedBreaks: 0)
    }

    func save(_ record: HealthReminderDayRecord) {
        var all = records()
        all[record.date] = record
        let trimmed = all.values
            .sorted { $0.date > $1.date }
            .prefix(maxRecords)
        let next = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.date, $0) })
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: Key.records)
    }

    static func todayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func records() -> [String: HealthReminderDayRecord] {
        guard let data = defaults.data(forKey: Key.records),
              let decoded = try? JSONDecoder().decode([String: HealthReminderDayRecord].self, from: data)
        else { return [:] }
        return decoded
    }
}

@MainActor
final class HealthReminderService: ObservableObject {
    @Published private(set) var state: HealthReminderState

    var onStateChanged: ((HealthReminderState) -> Void)?
    var currentSettings: HealthReminderSettings {
        settings
    }

    private let store: HealthReminderStore
    private var settings: HealthReminderSettings = .default
    private var theme: AppTheme = .gingerCat
    private var timer: Timer?
    private var currentDate: String
    private var breakWindow: NSPanel?
    private var breakHostingController: NSHostingController<HealthBreakOverlayView>?
    private var activityGraceUntil: Date?

    init(store: HealthReminderStore = HealthReminderStore()) {
        self.store = store
        let date = HealthReminderStore.todayString()
        currentDate = date
        let record = store.record(for: date)
        state = HealthReminderState(
            phase: .idle,
            remainingSeconds: 0,
            completedBreaksToday: record.completedBreaks,
            skippedBreaksToday: record.skippedBreaks,
            activityPaused: false,
            pausedFrom: nil
        )
    }

    func apply(settings: AppSettings) {
        self.settings = settings.healthReminder.clamped()
        theme = settings.theme
        refreshDailyRecordIfNeeded()
        applyBreakWindowConfiguration()

        if self.settings.enabled {
            if state.phase == .idle {
                startWorking()
            }
            startTimerIfNeeded()
            refreshBreakWindow()
        } else {
            stop(resetCounts: false)
        }
    }

    func stop(resetCounts: Bool = false) {
        timer?.invalidate()
        timer = nil
        hideBreakWindow()
        let record = store.record(for: currentDate)
        state = HealthReminderState(
            phase: .idle,
            remainingSeconds: 0,
            completedBreaksToday: resetCounts ? 0 : record.completedBreaks,
            skippedBreaksToday: resetCounts ? 0 : record.skippedBreaks,
            activityPaused: false,
            pausedFrom: nil
        )
        notifyStateChanged()
    }

    func startWorking() {
        refreshDailyRecordIfNeeded()
        hideBreakWindow()
        updateState(
            phase: .working,
            remainingSeconds: max(1, settings.workMinutes) * 60,
            activityPaused: false,
            pausedFrom: nil
        )
        startTimerIfNeeded()
    }

    func pauseOrResume() {
        switch state.phase {
        case .working, .breakReady, .breaking:
            timer?.invalidate()
            timer = nil
            hideBreakWindow()
            updateState(phase: .paused, activityPaused: false, pausedFrom: state.phase)
        case .paused:
            let next = state.pausedFrom ?? .working
            updateState(phase: next, activityPaused: false, pausedFrom: nil)
            startTimerIfNeeded()
            refreshBreakWindow()
        case .idle:
            startWorking()
        }
    }

    func startBreak() {
        refreshDailyRecordIfNeeded()
        activityGraceUntil = Date().addingTimeInterval(3)
        updateState(
            phase: .breaking,
            remainingSeconds: max(10, settings.breakSeconds),
            activityPaused: false,
            pausedFrom: nil
        )
        playSoundIfNeeded()
        startTimerIfNeeded()
        showBreakWindow()
    }

    func skipBreak() {
        guard state.phase == .breakReady || state.phase == .breaking else { return }
        refreshDailyRecordIfNeeded()
        var record = store.record(for: currentDate)
        record.skippedBreaks += 1
        store.save(record)
        state.completedBreaksToday = record.completedBreaks
        state.skippedBreaksToday = record.skippedBreaks
        startWorking()
    }

    func completeBreak() {
        refreshDailyRecordIfNeeded()
        var record = store.record(for: currentDate)
        record.completedBreaks += 1
        store.save(record)
        state.completedBreaksToday = record.completedBreaks
        state.skippedBreaksToday = record.skippedBreaks
        startWorking()
    }

    func statusText() -> String {
        switch state.phase {
        case .idle:
            return L10n.healthStatusIdle
        case .working:
            return String(format: L10n.healthStatusWorking, formatTime(state.remainingSeconds))
        case .breakReady:
            return L10n.healthStatusBreakReady
        case .breaking:
            if state.activityPaused {
                return L10n.healthStatusActivityPaused
            }
            return String(format: L10n.healthStatusBreaking, formatTime(state.remainingSeconds))
        case .paused:
            return L10n.healthStatusPaused
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        refreshDailyRecordIfNeeded()
        guard settings.enabled else {
            stop(resetCounts: false)
            return
        }

        switch state.phase {
        case .working:
            if state.remainingSeconds <= 1 {
                updateState(phase: .breakReady, remainingSeconds: 0)
                playSoundIfNeeded()
                showBreakWindow()
            } else {
                updateState(remainingSeconds: state.remainingSeconds - 1)
            }
        case .breakReady:
            refreshBreakWindow()
        case .breaking:
            if settings.activityDetectionEnabled, shouldPauseForActivity() {
                updateState(activityPaused: true)
                refreshBreakWindow()
                return
            }

            if state.activityPaused, idleSeconds() >= 4 {
                updateState(activityPaused: false)
            }

            guard !state.activityPaused else {
                refreshBreakWindow()
                return
            }

            if state.remainingSeconds <= 1 {
                completeBreak()
            } else {
                updateState(remainingSeconds: state.remainingSeconds - 1)
                refreshBreakWindow()
            }
        case .paused, .idle:
            break
        }
    }

    private func shouldPauseForActivity() -> Bool {
        if let activityGraceUntil, Date() < activityGraceUntil {
            return false
        }
        return idleSeconds() < 2.5
    }

    private func idleSeconds() -> TimeInterval {
        let events: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .mouseMoved,
            .scrollWheel,
            .otherMouseDown,
        ]
        return events
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func refreshDailyRecordIfNeeded() {
        let today = HealthReminderStore.todayString()
        guard today != currentDate else { return }
        currentDate = today
        let record = store.record(for: today)
        state.completedBreaksToday = record.completedBreaks
        state.skippedBreaksToday = record.skippedBreaks
        notifyStateChanged()
    }

    private func updateState(
        phase: HealthReminderPhase? = nil,
        remainingSeconds: Int? = nil,
        activityPaused: Bool? = nil,
        pausedFrom: HealthReminderPhase?? = nil
    ) {
        if let phase { state.phase = phase }
        if let remainingSeconds { state.remainingSeconds = max(0, remainingSeconds) }
        if let activityPaused { state.activityPaused = activityPaused }
        if let pausedFrom { state.pausedFrom = pausedFrom }
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        onStateChanged?(state)
    }

    private func playSoundIfNeeded() {
        guard settings.soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    private func showBreakWindow() {
        ensureBreakWindow()
        refreshBreakWindow()
        guard let breakWindow else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let x = frame.midX - breakWindow.frame.width / 2
            let y = frame.midY - breakWindow.frame.height / 2
            breakWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
        breakWindow.orderFrontRegardless()
    }

    private func refreshBreakWindow() {
        guard state.phase == .breakReady || state.phase == .breaking else {
            hideBreakWindow()
            return
        }
        ensureBreakWindow()
        breakHostingController?.rootView = breakView()
    }

    private func ensureBreakWindow() {
        guard breakWindow == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: breakView())
        panel.contentViewController = hosting
        breakWindow = panel
        breakHostingController = hosting
        applyBreakWindowConfiguration()
    }

    private func hideBreakWindow() {
        breakWindow?.orderOut(nil)
    }

    private func applyBreakWindowConfiguration() {
        breakWindow?.level = settings.breakMode == .strict ? .statusBar : .floating
    }

    private func breakView() -> HealthBreakOverlayView {
        HealthBreakOverlayView(
            state: state,
            settings: settings,
            theme: theme,
            onStartBreak: { [weak self] in
                self?.activityGraceUntil = Date().addingTimeInterval(3)
                self?.startBreak()
            },
            onSkip: { [weak self] in
                self?.activityGraceUntil = Date().addingTimeInterval(3)
                self?.skipBreak()
            },
            onDone: { [weak self] in
                self?.completeBreak()
            }
        )
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private extension HealthReminderSettings {
    func clamped() -> HealthReminderSettings {
        var copy = self
        copy.workMinutes = min(max(copy.workMinutes, 5), 180)
        copy.breakSeconds = min(max(copy.breakSeconds, 10), 1800)
        copy.dailyGoal = min(max(copy.dailyGoal, 1), 24)
        return copy
    }
}
