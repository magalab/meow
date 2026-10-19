import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct AppHealthReminderCoordinatorTests {
    @Test
    func commandsPreserveEnablePauseAndSkipRules() {
        var enabled = false
        var enableCount = 0
        var startCount = 0
        var pauseCount = 0
        var breakCount = 0
        var skipCount = 0
        let coordinator = AppHealthReminderCoordinator(actions: .init(
            isEnabled: { enabled },
            enable: { enabled = true; enableCount += 1 },
            startWorking: { startCount += 1 },
            pauseOrResume: { pauseCount += 1 },
            startBreak: { breakCount += 1 },
            skipBreak: { skipCount += 1 }
        ))

        coordinator.handle(.start)
        #expect(enabled)
        #expect(enableCount == 1)
        #expect(startCount == 1)

        coordinator.handle(.pauseResume)
        #expect(pauseCount == 1)

        enabled = false
        coordinator.handle(.pauseResume)
        #expect(enabled)
        #expect(enableCount == 2)
        #expect(pauseCount == 1)

        enabled = false
        coordinator.handle(.startBreak)
        #expect(enabled)
        #expect(enableCount == 3)
        #expect(breakCount == 1)

        enabled = false
        coordinator.handle(.skipBreak)
        #expect(skipCount == 0)
        enabled = true
        coordinator.handle(.skipBreak)
        #expect(skipCount == 1)
    }
}
