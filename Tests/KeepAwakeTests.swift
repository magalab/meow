import Foundation
import IOKit.pwr_mgt
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

/// Simplified mock: assertion IDs never repeat. Real IOKit may reuse IDs after
/// system sleep; tests for that path should configure a dedicated mock.
@MainActor
private final class MockKeepAwakeDriver: KeepAwakeAsserting {
    var nextAssertionID: IOPMAssertionID = 100
    var acquiredModes: [KeepAwakeMode] = []
    var releaseAttempts: [IOPMAssertionID] = []
    var releasedIDs: [IOPMAssertionID] = []
    var acquireError: Error?
    var releaseError: Error?
    var releaseDelay: Duration?
    var acquireDelay: Duration?
    var acquireStarted = false
    var assertionPresence: KeepAwakeAssertionPresence = .owned
    var reconciledIDs: [IOPMAssertionID] = []
    var pendingAssertionIDs: Set<IOPMAssertionID> = []
    var cleanupError: Error?
    var systemWillSleepCalls = 0
    var systemDidWakeCalls = 0
    var reconcileDelay: Duration?
    var inSleepTransition = false

    func acquire(for mode: KeepAwakeMode) async throws -> IOPMAssertionID {
        if let acquireError {
            throw acquireError
        }
        acquireStarted = true
        if let acquireDelay {
            try await Task.sleep(for: acquireDelay)
        }
        let assertionID = nextAssertionID
        nextAssertionID += 1
        acquiredModes.append(mode)
        return assertionID
    }

    func release(_ assertionID: IOPMAssertionID) async throws {
        releaseAttempts.append(assertionID)
        if let releaseDelay {
            try await Task.sleep(for: releaseDelay)
        }
        if let releaseError {
            throw releaseError
        }
        releasedIDs.append(assertionID)
    }

    func reconcile(_ assertionID: IOPMAssertionID) async -> KeepAwakeAssertionPresence {
        reconciledIDs.append(assertionID)
        if let reconcileDelay {
            try? await Task.sleep(for: reconcileDelay)
        }
        return assertionPresence
    }

    func cleanupPendingAssertions() async throws {
        if let cleanupError {
            throw cleanupError
        }
        for assertionID in Array(pendingAssertionIDs) {
            switch await reconcile(assertionID) {
            case .owned:
                if inSleepTransition {
                    continue
                }
                try await release(assertionID)
                pendingAssertionIDs.remove(assertionID)
            case .missing, .notOwned:
                pendingAssertionIDs.remove(assertionID)
            }
        }
    }

    func systemWillSleep() {
        systemWillSleepCalls += 1
        inSleepTransition = true
    }

    func systemDidWake() {
        systemDidWakeCalls += 1
        inSleepTransition = false
    }
}

private final class KeepAwakeTestClock: @unchecked Sendable {
    var instant = ContinuousClock().now
}

private func keepAwakeSleeper() async throws {
    try await Task.sleep(for: .seconds(3_600))
}

private enum KeepAwakeTestError: Error {
    case timeout
}

@MainActor
private func waitForKeepAwakeCondition(
    timeout: Duration = .milliseconds(500),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock().now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock().now < deadline else {
            throw KeepAwakeTestError.timeout
        }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch is CancellationError {
            throw CancellationError()
        }
    }
}

@Test("Older settings default Keep Awake to disabled")
func olderSettingsCompatibilityDefaultsKeepAwake() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

    #expect(settings.keepAwake == .default)
    #expect(!settings.keepAwake.enabled)
    #expect(settings.keepAwake.mode == .system)
    #expect(settings.keepAwake.duration == .thirtyMinutes)
}

@Test("Keep Awake cannot start while disabled")
@MainActor
func keepAwakeDisabledCannotStart() async {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })

    do {
        try await service.start()
        Issue.record("Expected disabled Keep Awake to reject start")
    } catch let error as KeepAwakeError {
        #expect(error == .disabled)
        #expect(service.state == .idle)
        #expect(driver.acquiredModes.isEmpty)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("Keep Awake settings round trip")
func keepAwakeSettingsRoundTrip() throws {
    var settings = AppSettings.default
    settings.keepAwake = KeepAwakeSettings(
        enabled: true,
        mode: .display,
        duration: .fiveMinutes
    )

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

    #expect(decoded.keepAwake == settings.keepAwake)
}

@Test("Keep Awake maps the selected mode and releases its exact assertion")
@MainActor
func keepAwakeStartsAndStops() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .fifteenMinutes
        )
    )

    try await service.start()

    #expect(driver.acquiredModes == [.display])
    #expect(service.activeSession?.mode == .display)
    #expect(service.activeSession?.duration == .fifteenMinutes)
    let assertionID = driver.nextAssertionID - 1

    await service.stop()

    #expect(driver.releasedIDs == [assertionID])
    #expect(service.activeSession == nil)
}

@Test("Changing defaults does not alter the active Keep Awake session")
@MainActor
func keepAwakeSettingsChangeDoesNotAlterActiveSession() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .fiveMinutes
        )
    )

    #expect(service.currentSettings.mode == .display)
    #expect(service.currentSettings.duration == .fiveMinutes)
    #expect(service.activeSession?.mode == .system)
    #expect(service.activeSession?.duration == .thirtyMinutes)

    await service.stop()
}

@Test("Disabling and re-enabling Keep Awake does not release an assertion twice")
@MainActor
func keepAwakeDisableReenableUsesEachAssertionOnce() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    let enabledSettings = KeepAwakeSettings(
        enabled: true,
        mode: .system,
        duration: .fifteenMinutes
    )

    service.apply(settings: enabledSettings)
    try await service.start()
    service.apply(settings: .default)
    try await waitForKeepAwakeCondition { driver.releaseAttempts == [100] }

    #expect(service.state == .idle)
    #expect(service.activeSession == nil)
    #expect(service.remainingMinutes == nil)
    #expect(driver.releaseAttempts == [100])

    service.apply(settings: enabledSettings)
    try await service.start()
    await service.stop()

    #expect(driver.releaseAttempts == [100, 101])
    #expect(driver.releasedIDs == [100, 101])
}

@Test("Stop release failures are visible and can be retried")
@MainActor
func keepAwakeStopReleaseFailureIsVisibleAndRetried() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fifteenMinutes
        )
    )
    try await service.start()

    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    await service.stop()

    #expect(service.state.errorMessage != nil)
    #expect(driver.releaseAttempts == [100, 100, 100])

    driver.releaseError = nil
    try await service.start()
    await service.stop()

    #expect(driver.releaseAttempts == [100, 100, 100, 100, 101])
    #expect(driver.releasedIDs == [100, 101])
}

@Test("Disabling Keep Awake reports a background release failure")
@MainActor
func keepAwakeDisableReleaseFailureIsVisible() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .fifteenMinutes
        )
    )
    try await service.start()

    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .display,
        assertionID: 100,
        status: -536870212
    )
    service.apply(settings: .default)
    try await waitForKeepAwakeCondition { service.state.errorMessage != nil }

    #expect(service.state.errorMessage != nil)
    #expect(driver.releaseAttempts == [100])
}

@Test("Disabling Keep Awake while active stops the session")
@MainActor
func keepAwakeDisableStopsActiveSession() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    let enabledSettings = KeepAwakeSettings(
        enabled: true,
        mode: .system,
        duration: .fifteenMinutes
    )
    service.apply(settings: enabledSettings)
    try await service.start()

    service.apply(settings: .default)
    try await waitForKeepAwakeCondition { driver.releasedIDs == [100] }

    #expect(service.state == .idle)
    #expect(service.activeSession == nil)
    #expect(service.remainingMinutes == nil)
    #expect(driver.releaseAttempts == [100])
    #expect(driver.releasedIDs == [100])
}

@Test("Settings changes during start do not alter the in-flight session")
@MainActor
func keepAwakeSettingsChangeDuringStartDoesNotAlterSession() async throws {
    let driver = MockKeepAwakeDriver()
    driver.acquireDelay = .milliseconds(50)
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    let systemSettings = KeepAwakeSettings(
        enabled: true,
        mode: .system,
        duration: .fifteenMinutes
    )
    let displaySettings = KeepAwakeSettings(
        enabled: true,
        mode: .display,
        duration: .fiveMinutes
    )
    service.apply(settings: systemSettings)

    let startTask = Task { @MainActor in
        try? await service.start()
    }
    try await waitForKeepAwakeCondition { driver.acquireStarted }

    service.apply(settings: displaySettings)
    await startTask.value

    #expect(service.activeSession?.mode == .system)
    #expect(service.activeSession?.duration == .fifteenMinutes)

    await service.stop()
}

@Test("Keep Awake and recording-style assertions release only their own IDs")
@MainActor
func keepAwakeAndRecordingAssertionsRemainIndependent() async throws {
    let keepAwakeDriver = MockKeepAwakeDriver()
    let recordingDriver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: keepAwakeDriver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .fifteenMinutes
        )
    )

    try await service.start()
    let recordingAssertionID = try await recordingDriver.acquire(for: .display)

    await service.stop()

    #expect(keepAwakeDriver.releasedIDs == [100])
    #expect(recordingDriver.releasedIDs.isEmpty)

    try await recordingDriver.release(recordingAssertionID)
    #expect(recordingDriver.releasedIDs == [recordingAssertionID])
}

@Test("Indefinite Keep Awake has no expiration")
@MainActor
func indefiniteKeepAwakeHasNoExpiration() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .indefinite
        )
    )

    try await service.start()

    #expect(service.activeSession?.duration == .indefinite)
    #expect(service.remainingMinutes == nil)

    await service.stop()
}

@Test("Assertion creation failure never becomes an active session")
@MainActor
func keepAwakeCreationFailureDoesNotBecomeActive() async {
    let driver = MockKeepAwakeDriver()
    driver.acquireError = KeepAwakeError.assertionCreateFailed(mode: .system, status: -536870212)
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    do {
        try await service.start()
        Issue.record("Expected Keep Awake start to fail")
    } catch {
        #expect(service.activeSession == nil)
        #expect(service.state.errorMessage != nil)
        #expect(driver.releasedIDs.isEmpty)
    }
}

@Test("Pending rollback cleanup reconciles ownership before releasing")
@MainActor
func keepAwakePendingRollbackReconcilesBeforeRelease() async throws {
    let driver = MockKeepAwakeDriver()
    driver.pendingAssertionIDs = [700]
    driver.assertionPresence = .notOwned
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fifteenMinutes
        )
    )

    try await service.start()

    #expect(driver.reconciledIDs == [700])
    #expect(driver.releaseAttempts.isEmpty)
    #expect(driver.acquiredModes == [.system])

    await service.stop()
}

@Test("Pending driver cleanup defers release across a system sleep transition")
@MainActor
func keepAwakePendingRollbackDefersReleaseAcrossSleep() async throws {
    let driver = MockKeepAwakeDriver()
    driver.pendingAssertionIDs = [700]
    driver.reconcileDelay = .milliseconds(50)
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fifteenMinutes
        )
    )

    let startTask = Task { @MainActor in
        try? await service.start()
    }
    try await waitForKeepAwakeCondition { driver.reconciledIDs == [700] }
    service.systemWillSleep()
    await startTask.value

    #expect(driver.systemWillSleepCalls == 1)
    #expect(driver.releaseAttempts.isEmpty)
    #expect(driver.pendingAssertionIDs == [700])

    service.systemDidWake()
    try await service.start()

    #expect(driver.systemDidWakeCalls == 1)
    #expect(driver.releaseAttempts == [700])
    #expect(driver.acquiredModes == [.system])

    await service.stop()
}

@Test("Expiration stops a timed Keep Awake session")
@MainActor
func keepAwakeExpirationStopsSession() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in },
        sleepFor: { _ in try await keepAwakeSleeper() }
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fiveMinutes
        )
    )

    try await service.start()
    try await waitForKeepAwakeCondition { service.state == .idle && driver.releasedIDs == [100] }

    #expect(service.state == .idle)
    #expect(service.activeSession == nil)
    #expect(service.remainingMinutes == nil)
    #expect(driver.releasedIDs == [100])
}

@Test("Changing settings clears an unavailable Keep Awake state")
@MainActor
func keepAwakeUnavailableStateRecoversAfterSettingsChange() async {
    let driver = MockKeepAwakeDriver()
    driver.acquireError = KeepAwakeError.assertionCreateFailed(mode: .system, status: -536870212)
    let service = KeepAwakeService(driver: driver)
    let initialSettings = KeepAwakeSettings(
        enabled: true,
        mode: .system,
        duration: .thirtyMinutes
    )
    service.apply(settings: initialSettings)

    do {
        try await service.start()
        Issue.record("Expected Keep Awake start to fail")
    } catch {
        #expect(service.state.errorMessage != nil)
    }

    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .thirtyMinutes
        )
    )

    #expect(service.state == .idle)
}

@Test("Repeated start and stop operations do not reuse the wrong assertion")
@MainActor
func keepAwakeRepeatedStartStopUsesExactIDs() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fiveMinutes
        )
    )

    try await service.start()
    await service.stop()
    try await service.start()
    let secondAssertionID = driver.nextAssertionID - 1
    await service.stop()

    #expect(driver.acquiredModes == [.system, .system])
    #expect(driver.releasedIDs == [100, secondAssertionID])
    #expect(secondAssertionID != 100)
}

@Test("Start releases service assertions before driver cleanup")
@MainActor
func keepAwakeStartPreservesServiceAssertionsWhenDriverCleanupFails() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    let settings = KeepAwakeSettings(
        enabled: true,
        mode: .system,
        duration: .thirtyMinutes
    )
    service.apply(settings: settings)

    try await service.start()
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    await service.stop()
    #expect(service.state.errorMessage != nil)
    #expect(driver.releasedIDs.isEmpty)

    driver.releaseError = nil
    driver.cleanupError = KeepAwakeError.assertionRollbackFailed(
        assertionID: 900,
        status: -536870212
    )

    do {
        try await service.start()
        Issue.record("Expected driver cleanup to fail")
    } catch {
        #expect(service.state.errorMessage != nil)
    }

    #expect(driver.releaseAttempts == [100, 100])
    #expect(driver.releasedIDs == [100])
    #expect(driver.acquiredModes == [.system])
}

@Test("A concurrent stop invalidates an in-flight start")
@MainActor
func keepAwakeConcurrentStartAndStopEndsIdle() async throws {
    let driver = MockKeepAwakeDriver()
    driver.acquireDelay = .milliseconds(50)
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() }
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fifteenMinutes
        )
    )

    let startTask = Task { @MainActor in
        try? await service.start()
    }
    do {
        try await waitForKeepAwakeCondition { driver.acquireStarted }
    } catch {
        startTask.cancel()
        await service.stop()
        await startTask.value
        throw error
    }

    await service.stop()
    await startTask.value
    try await waitForKeepAwakeCondition { driver.releasedIDs == [100] }

    #expect(driver.acquireStarted)
    #expect(service.state == .idle)
    #expect(service.activeSession == nil)
    #expect(driver.releasedIDs == [100])
}

@Test("A system sleep ends the current Keep Awake session")
@MainActor
func keepAwakeSystemSleepEndsSession() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(driver: driver, sleepUntil: { _ in try await keepAwakeSleeper() })
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    service.systemWillSleep()

    #expect(driver.systemWillSleepCalls == 1)
    #expect(service.state == .idle)
    #expect(service.activeSession == nil)
    try await waitForKeepAwakeCondition { driver.releasedIDs == [100] }
    #expect(driver.reconciledIDs.isEmpty)
    service.systemDidWake()
    #expect(driver.systemDidWakeCalls == 1)
    #expect(service.state == .idle)
}

@Test("System sleep captures an in-flight ordinary release")
@MainActor
func keepAwakeSystemSleepCapturesInFlightRelease() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    driver.releaseDelay = .milliseconds(50)
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    let stopTask = Task { @MainActor in
        await service.stop()
    }

    try await waitForKeepAwakeCondition { driver.releaseAttempts == [100] }
    service.systemWillSleep()
    await stopTask.value

    driver.assertionPresence = .missing
    service.systemDidWake()
    try await waitForKeepAwakeCondition { driver.reconciledIDs == [100] }

    #expect(driver.releasedIDs.isEmpty)
    #expect(service.state == .idle)
}

@Test("System sleep captures an in-flight disabled-setting release")
@MainActor
func keepAwakeSystemSleepCapturesInFlightDisabledRelease() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .display,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    driver.releaseDelay = .milliseconds(50)
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .display,
        assertionID: 100,
        status: -536870212
    )
    service.apply(settings: .default)

    try await waitForKeepAwakeCondition { driver.releaseAttempts == [100] }
    service.systemWillSleep()
    try await waitForKeepAwakeCondition { service.state.errorMessage != nil }

    driver.assertionPresence = .missing
    service.systemDidWake()
    try await waitForKeepAwakeCondition { driver.reconciledIDs == [100] }

    #expect(driver.releasedIDs.isEmpty)
    #expect(service.state == .idle)
}

@Test("System wake reconciles an assertion that could not be released before sleep")
@MainActor
func keepAwakeSystemWakeReconcilesUnreleasedAssertion() async throws {
    let driver = MockKeepAwakeDriver()
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    driver.assertionPresence = .missing
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    service.systemWillSleep()
    try await waitForKeepAwakeCondition { service.state.errorMessage != nil }

    service.systemDidWake()
    try await waitForKeepAwakeCondition { driver.reconciledIDs == [100] }

    #expect(driver.releasedIDs.isEmpty)
    #expect(service.state == .idle)
}

@Test("System sleep also transfers previously unreleased assertions")
@MainActor
func keepAwakeSystemSleepIncludesPreviouslyUnreleasedAssertions() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    await service.stop()
    try await waitForKeepAwakeCondition { service.state.errorMessage != nil }

    driver.releaseError = nil
    service.systemWillSleep()
    try await waitForKeepAwakeCondition { driver.releaseAttempts == [100, 100] }

    #expect(driver.releasedIDs == [100])
    #expect(service.state == .idle)
}

@Test("Stopping after a cancelled sleep transition releases its pending assertion")
@MainActor
func keepAwakeStopSettlesCancelledSleepTransition() async throws {
    let driver = MockKeepAwakeDriver()
    let service = KeepAwakeService(
        driver: driver,
        sleepUntil: { _ in try await keepAwakeSleeper() },
        releaseRetryDelays: []
    )
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .thirtyMinutes
        )
    )

    try await service.start()
    driver.releaseError = KeepAwakeError.assertionReleaseFailed(
        mode: .system,
        assertionID: 100,
        status: -536870212
    )
    service.systemWillSleep()
    try await waitForKeepAwakeCondition { service.state.errorMessage != nil }

    await service.stop()
    #expect(service.state.errorMessage != nil)

    driver.releaseError = nil
    await service.stop()

    #expect(driver.releasedIDs == [100])
    #expect(service.state == .idle)
}

@Test("Keep Awake remaining time uses a monotonic clock")
@MainActor
func keepAwakeRemainingTimeIgnoresWallClockChanges() async throws {
    let driver = MockKeepAwakeDriver()
    let clock = KeepAwakeTestClock()
    var updatedRemainingMinutes: [Int?] = []
    let service = KeepAwakeService(
        driver: driver,
        now: { clock.instant },
        sleepUntil: { _ in try await keepAwakeSleeper() },
        sleepFor: { _ in try await Task.sleep(for: .milliseconds(1)) }
    )
    service.onRemainingTimeChanged = { updatedRemainingMinutes.append($0) }
    service.apply(
        settings: KeepAwakeSettings(
            enabled: true,
            mode: .system,
            duration: .fifteenMinutes
        )
    )

    try await service.start()
    #expect(service.remainingMinutes == 15)

    clock.instant = clock.instant.advanced(by: .seconds(180))
    try await waitForKeepAwakeCondition { service.remainingMinutes == 12 }
    #expect(service.remainingMinutes == 12)
    #expect(updatedRemainingMinutes.contains(12))

    await service.stop()
}

@Test("Keep Awake localization keys exist in both shipped languages")
func keepAwakeLocalizationIsComplete() throws {
    let resourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Resources", isDirectory: true)
    let keys = [
        "keep.awake.enabled.title",
        "keep.awake.enabled.subtitle",
        "keep.awake.mode.title",
        "keep.awake.mode.system",
        "keep.awake.mode.display",
        "keep.awake.duration.title",
        "keep.awake.duration.five.minutes",
        "keep.awake.duration.fifteen.minutes",
        "keep.awake.duration.thirty.minutes",
        "keep.awake.duration.sixty.minutes",
        "keep.awake.duration.one.hundred.twenty.minutes",
        "keep.awake.duration.indefinite",
        "keep.awake.status.title",
        "keep.awake.status.idle",
        "keep.awake.status.starting",
        "keep.awake.status.unavailable",
        "keep.awake.stop",
        "keep.awake.battery.warning.title",
        "keep.awake.battery.warning",
        "keep.awake.recording.overlap.title",
        "keep.awake.recording.overlap",
        "keep.awake.error.title",
        "keep.awake.unavailable.message",
        "keep.awake.remaining.minutes",
        "keep.awake.error.disabled",
        "keep.awake.error.cleanup.pending",
        "keep.awake.error.invalid.assertion.id",
        "keep.awake.error.assertion.create.failed",
        "keep.awake.error.assertion.mode",
        "keep.awake.error.assertion.release.failed",
        "keep.awake.error.assertion.rollback.failed",
        "cmd.keep.awake.start.title",
        "cmd.keep.awake.configured.subtitle",
        "cmd.keep.awake.stop.title",
        "cmd.keep.awake.starting.subtitle",
        "cmd.keep.awake.active.subtitle",
        "cmd.keep.awake.unavailable.subtitle",
    ]

    for language in ["en", "zh-Hans"] {
        let url = resourceRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let localizable = try String(contentsOf: url, encoding: .utf8)
        for key in keys {
            #expect(localizable.contains("\"\(key)\" ="))
        }
    }
}

#if DEBUG
@Test("Keep Awake real IOKit smoke test (opt-in)")
@MainActor
func keepAwakeRealIOKitSmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["MEOW_RUN_KEEP_AWAKE_INTEGRATION"] == "1" else {
        return
    }

    let driver = IOKitKeepAwakeAssertionDriver()
    let assertionID = try await driver.acquire(for: .system)
    do {
        try await driver.release(assertionID)
    } catch {
        try? await driver.release(assertionID)
        throw error
    }
}
#endif
