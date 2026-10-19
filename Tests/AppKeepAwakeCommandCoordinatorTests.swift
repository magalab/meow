import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
private final class KeepAwakeCommandTestState {
    var shouldCancel = true
    var presentedErrors: [String] = []
}

@MainActor
struct AppKeepAwakeCommandCoordinatorTests {
    @Test
    func cancellationIsSilentAndOtherErrorsArePresented() async {
        let state = KeepAwakeCommandTestState()
        let coordinator = AppKeepAwakeCommandCoordinator(actions: .init(
            hideLauncher: {},
            toggleKeepAwake: {
                if state.shouldCancel {
                    throw CancellationError()
                }
                throw NSError(domain: "keep-awake-test", code: 1)
            },
            presentError: { state.presentedErrors.append($0.localizedDescription) }
        ))

        await coordinator.toggleKeepAwake()
        #expect(state.presentedErrors.isEmpty)

        state.shouldCancel = false
        await coordinator.toggleKeepAwake()
        #expect(state.presentedErrors.count == 1)
        #expect(state.presentedErrors[0].contains("keep-awake-test"))
    }
}
