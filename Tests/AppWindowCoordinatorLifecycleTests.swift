import AppKit
import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Suite("App window coordinator lifecycle")
@MainActor
struct AppWindowCoordinatorLifecycleTests {
    @Test
    func eventMonitorsInstallAndRemoveIdempotently() {
        var globalHandlers: [(NSEvent) -> Void] = []
        var localHandlers: [(NSEvent) -> NSEvent?] = []
        var removedTokens: [UUID] = []
        let driver = AppWindowCoordinator.EventMonitorDriver(
            addGlobal: { _, handler in
                globalHandlers.append(handler)
                return UUID()
            },
            addLocal: { _, handler in
                localHandlers.append(handler)
                return UUID()
            },
            remove: { token in
                if let token = token as? UUID {
                    removedTokens.append(token)
                }
            }
        )
        let coordinator = AppWindowCoordinator(eventMonitorDriver: driver)
        var cancellationCount = 0
        let actions = AppWindowCoordinator.EventMonitorActions(
            dismissLauncher: {},
            dismissTranslation: {},
            dismissTextActions: {},
            dismissCalendarPopover: {},
            statusItemButton: { nil },
            cancelSpeechIfActive: {
                cancellationCount += 1
                return false
            },
            showPreferences: {}
        )

        coordinator.installEventMonitors(actions: actions)
        coordinator.installEventMonitors(actions: actions)

        #expect(globalHandlers.count == 2)
        #expect(localHandlers.count == 2)
        let savedEscapeHandler = localHandlers[1]
        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 53
        )!

        _ = savedEscapeHandler(escapeEvent)
        #expect(cancellationCount == 1)

        coordinator.removeEventMonitors()
        coordinator.removeEventMonitors()

        #expect(removedTokens.count == 4)
        _ = savedEscapeHandler(escapeEvent)
        #expect(cancellationCount == 1)
    }
}
