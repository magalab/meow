import AppKit

@MainActor
final class AppCalendarCoordinator {
    struct Actions {
        let statusItemButton: @MainActor () -> NSButton?
        let theme: @MainActor () -> AppTheme
        let handleHealthCommand: @MainActor (HealthReminderCommand) -> Void
        let openHealthPreferences: @MainActor () -> Void
    }

    private let windowCoordinator: AppWindowCoordinator
    private let healthReminderService: HealthReminderService
    private let actions: Actions
    private var refreshToken = UUID()

    init(
        windowCoordinator: AppWindowCoordinator,
        healthReminderService: HealthReminderService,
        actions: Actions
    ) {
        self.windowCoordinator = windowCoordinator
        self.healthReminderService = healthReminderService
        self.actions = actions
    }

    func togglePopover() {
        guard let button = actions.statusItemButton() else { return }
        windowCoordinator.toggleCalendarPopover(
            contentView: { popover in makePopoverView(for: popover) },
            relativeTo: button
        )
    }

    func refresh() {
        refreshToken = UUID()
        windowCoordinator.refreshCalendar { popover in
            makePopoverView(for: popover)
        }
    }

    private func makePopoverView(for popover: NSPopover?) -> CalendarPopoverView {
        CalendarPopoverView(
            theme: actions.theme(),
            healthReminderService: healthReminderService,
            onHealthCommand: actions.handleHealthCommand,
            onOpenHealthPreferences: actions.openHealthPreferences,
            onContentSizeChanged: { [weak popover] size in
                popover?.contentSize = size
            },
            refreshToken: refreshToken
        )
    }
}
