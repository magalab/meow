import AppKit
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct MouseClickHighlighterLifecycleTests {
    @Test("Mouse click monitors are not duplicated and are removed across pause and stop")
    func monitorLifecycleIsIdempotent() {
        var globalAdds = 0
        var localAdds = 0
        var removals = 0
        var panelPreparations = 0
        let driver = MouseClickHighlighterController.EventMonitorDriver(
            addGlobal: { _, _ in globalAdds += 1; return NSObject() },
            addLocal: { _, _ in localAdds += 1; return NSObject() },
            remove: { _ in removals += 1 }
        )
        let controller = MouseClickHighlighterController(
            eventMonitorDriver: driver,
            preparePanelForMonitoring: { panelPreparations += 1 }
        )

        controller.start()
        controller.start()
        #expect(globalAdds == 1)
        #expect(localAdds == 1)
        #expect(panelPreparations == 1)

        controller.pause()
        controller.pause()
        #expect(removals == 2)

        controller.start()
        controller.stop()
        controller.stop()
        #expect(globalAdds == 2)
        #expect(localAdds == 2)
        #expect(panelPreparations == 2)
        #expect(removals == 4)
    }
}
