import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeService: ObservableObject {
    private enum ReleaseFailureDestination {
        case regular
        case sleepTransition(UUID)
        case afterWake
    }

    @Published private(set) var state: KeepAwakeState = .idle
    @Published private(set) var remainingMinutes: Int?

    var onStateChanged: ((KeepAwakeState) -> Void)?
    var onRemainingTimeChanged: ((Int?) -> Void)?
    var currentSettings: KeepAwakeSettings {
        settings
    }

    var isStartingOrActive: Bool {
        state.isStartingOrActive
    }

    var activeSession: KeepAwakeSession? {
        state.activeSession
    }

    private let driver: KeepAwakeAsserting
    private let now: @Sendable () -> ContinuousClock.Instant
    private let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    private let sleepFor: @Sendable (Duration) async throws -> Void
    private let releaseRetryDelays: [Duration]
    private var settings = KeepAwakeSettings.default
    private var currentAssertionID: IOPMAssertionID?
    private var currentSession: KeepAwakeSession?
    private var expirationInstant: ContinuousClock.Instant?
    private var expirationTask: Task<Void, Never>?
    private var remainingTimeTask: Task<Void, Never>?
    private var operationToken = UUID()
    private var sleepGeneration = 0
    private var unreleasedAssertionIDs = Set<IOPMAssertionID>()
    private var sleepPendingAssertionIDs = Set<IOPMAssertionID>()
    private var sleepPendingRevision = 0
    private var sleepTransitionToken: UUID?
    private var sleepDidWake = false
    private var sleepCleanupTask: Task<Void, Never>?
    private var sleepReconciliationTask: Task<Void, Never>?
    private var inFlightReleaseTasks: [IOPMAssertionID: Task<KeepAwakeError?, Never>] = [:]
    private var inFlightReleaseDestinations: [IOPMAssertionID: ReleaseFailureDestination] = [:]

    init(
        driver: KeepAwakeAsserting = IOKitKeepAwakeAssertionDriver(),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now },
        sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void = { instant in
            try await ContinuousClock().sleep(until: instant)
        },
        sleepFor: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await ContinuousClock().sleep(for: duration)
        },
        releaseRetryDelays: [Duration] = [.milliseconds(25), .milliseconds(100)]
    ) {
        self.driver = driver
        self.now = now
        self.sleepUntil = sleepUntil
        self.sleepFor = sleepFor
        self.releaseRetryDelays = releaseRetryDelays
    }

    func apply(settings: KeepAwakeSettings) {
        let settingsChanged = self.settings != settings
        self.settings = settings

        if !settings.enabled {
            let token = UUID()
            operationToken = token
            clearSessionMetadata()
            let assertionIDs = takeAssertionIDs()
            setState(.idle)
            releaseInBackground(assertionIDs, operationToken: token, reportError: true)
        } else if settingsChanged, state.errorMessage != nil, !hasPendingAssertionCleanup {
            setState(.idle)
        }
    }

    func toggle() async throws {
        if isStartingOrActive {
            await stop()
        } else {
            try await start()
        }
    }

    func start() async throws {
        guard settings.enabled else {
            throw KeepAwakeError.disabled
        }

        let mode = settings.mode
        let duration = settings.duration
        try await settlePendingOperationsBeforeStart()

        let token = UUID()
        let startSleepGeneration = sleepGeneration
        operationToken = token
        clearSessionMetadata()
        let assertionIDs = takeAssertionIDs()
        setState(.starting)

        do {
            if let error = await releaseAssertions(assertionIDs, operationToken: token, reportError: true) {
                throw error
            }
            try await driver.cleanupPendingAssertions()
            guard operationToken == token, settings.enabled else {
                throw CancellationError()
            }

            let assertionID = try await driver.acquire(for: mode)
            guard assertionID != 0 else {
                throw KeepAwakeError.invalidAssertionID(mode: mode)
            }

            guard !Task.isCancelled,
                  operationToken == token,
                  settings.enabled,
                  sleepGeneration == startSleepGeneration
            else {
                if sleepGeneration == startSleepGeneration {
                    _ = await releaseAssertionWithRetry(assertionID)
                } else {
                    addSleepPendingAssertion(assertionID)
                    scheduleSleepCleanupIfNeeded()
                }
                throw CancellationError()
            }

            let startedAt = Date()
            let expiresAt = duration.timeInterval.map { startedAt.addingTimeInterval($0) }
            let session = KeepAwakeSession(
                id: UUID(),
                mode: mode,
                duration: duration,
                startedAt: startedAt,
                expiresAt: expiresAt
            )
            currentAssertionID = assertionID
            currentSession = session
            expirationInstant = duration.duration.map { now().advanced(by: $0) }
            remainingMinutes = calculateRemainingMinutes()
            setState(.active(session))
            scheduleExpiration(for: session.id, token: token)
            scheduleRemainingTimeUpdates(for: session.id, token: token)
        } catch is CancellationError {
            if operationToken == token {
                setState(.idle)
            }
            throw CancellationError()
        } catch {
            if operationToken == token {
                currentAssertionID = nil
                currentSession = nil
                expirationInstant = nil
                setState(.unavailable(error.localizedDescription))
            }
            throw error
        }
    }

    func stop() async {
        await stop(reportReleaseErrors: true)
    }

    private func stop(reportReleaseErrors: Bool) async {
        await settlePendingOperationsBeforeStop()

        let token = UUID()
        operationToken = token
        clearSessionMetadata()
        let assertionIDs = takeAssertionIDs()
        if !hasPendingAssertionCleanup {
            setState(.idle)
        }

        _ = await releaseAssertions(
            assertionIDs,
            operationToken: token,
            reportError: reportReleaseErrors
        )
        _ = await cleanupDriverPendingAssertions(operationToken: token, reportError: reportReleaseErrors)
    }

    private func settleSleepTransition() async {
        guard sleepTransitionToken != nil || !sleepPendingAssertionIDs.isEmpty else { return }

        if let cleanupTask = sleepCleanupTask {
            await cleanupTask.value
        }

        if sleepDidWake {
            if let reconciliationTask = sleepReconciliationTask {
                await reconciliationTask.value
            }
        } else if let transitionToken = sleepTransitionToken, !sleepPendingAssertionIDs.isEmpty {
            await releaseSleepPendingAssertions(for: transitionToken)
        }
    }

    private func settlePendingOperationsBeforeStart() async throws {
        while true {
            try await resolvePendingSleepTransition()
            guard !inFlightReleaseTasks.isEmpty else { return }
            await settleInFlightReleases()
        }
    }

    private func settlePendingOperationsBeforeStop() async {
        while true {
            await settleSleepTransition()
            guard !inFlightReleaseTasks.isEmpty else { return }
            await settleInFlightReleases()
        }
    }

    private func settleInFlightReleases() async {
        while let task = inFlightReleaseTasks.values.first {
            _ = await task.value
        }
    }

    /// A will-sleep notification starts a power transition but does not prove
    /// that the machine actually slept. Keep assertion IDs until they are
    /// released or reconciled after a confirmed wake.
    func systemWillSleep() {
        driver.systemWillSleep()

        guard state == .starting
                || currentSession != nil
                || currentAssertionID != nil
                || !unreleasedAssertionIDs.isEmpty
                || !sleepPendingAssertionIDs.isEmpty
                || !inFlightReleaseTasks.isEmpty
        else { return }
        guard sleepTransitionToken == nil else { return }

        sleepGeneration += 1
        operationToken = UUID()
        clearSessionMetadata()
        let assertionIDs = takeAssertionIDs()
        addSleepPendingAssertions(assertionIDs)
        let transitionToken = UUID()
        sleepTransitionToken = transitionToken
        sleepDidWake = false
        let inFlightAssertionIDs = Set(inFlightReleaseTasks.keys)
        addSleepPendingAssertions(Array(inFlightAssertionIDs))
        for assertionID in inFlightAssertionIDs {
            inFlightReleaseDestinations[assertionID] = .sleepTransition(transitionToken)
        }
        setState(.idle)
        scheduleSleepCleanup(for: transitionToken)
    }

    func systemDidWake() {
        driver.systemDidWake()

        if let transitionToken = sleepTransitionToken {
            guard !sleepDidWake else { return }
            sleepDidWake = true
            let cleanupTask = sleepCleanupTask
            sleepReconciliationTask = Task { @MainActor [weak self, cleanupTask] in
                await cleanupTask?.value
                await self?.reconcileSleepPendingAssertions(for: transitionToken)
            }
            return
        }

        guard let session = currentSession,
              case .active = state
        else { return }

        guard let expirationInstant else {
            return
        }

        if now() >= expirationInstant {
            Task { @MainActor [weak self] in
                await self?.stop()
            }
        } else {
            scheduleExpiration(for: session.id, token: operationToken)
        }
    }

    private func scheduleExpiration(for sessionID: UUID, token: UUID) {
        expirationTask?.cancel()

        guard let expirationInstant else { return }
        let sleepUntil = self.sleepUntil
        expirationTask = Task { @MainActor [weak self, sleepUntil] in
            do {
                try await sleepUntil(expirationInstant)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.operationToken == token,
                  self.currentSession?.id == sessionID
            else { return }

            await self.stop()
        }
    }

    private func scheduleRemainingTimeUpdates(for sessionID: UUID, token: UUID) {
        remainingTimeTask?.cancel()

        guard expirationInstant != nil else { return }
        let sleepFor = self.sleepFor
        remainingTimeTask = Task { @MainActor [weak self, sleepFor] in
            while !Task.isCancelled {
                do {
                    try await sleepFor(.seconds(30))
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      let self,
                      self.operationToken == token,
                      self.currentSession?.id == sessionID,
                      self.expirationInstant != nil
                else { return }

                self.updateRemainingMinutes()
            }
        }
    }

    private func takeAssertionIDs() -> [IOPMAssertionID] {
        var assertionIDs = unreleasedAssertionIDs
        unreleasedAssertionIDs.removeAll()
        if let currentAssertionID {
            assertionIDs.insert(currentAssertionID)
            self.currentAssertionID = nil
        }
        return Array(assertionIDs)
    }

    private var hasPendingAssertionCleanup: Bool {
        !unreleasedAssertionIDs.isEmpty
            || !sleepPendingAssertionIDs.isEmpty
            || !inFlightReleaseTasks.isEmpty
            || sleepTransitionToken != nil
    }

    private func resolvePendingSleepTransition() async throws {
        guard sleepTransitionToken != nil || !sleepPendingAssertionIDs.isEmpty else { return }

        if let cleanupTask = sleepCleanupTask {
            await cleanupTask.value
        }

        if sleepDidWake {
            if let reconciliationTask = sleepReconciliationTask {
                await reconciliationTask.value
            }
        } else if let transitionToken = sleepTransitionToken, !sleepPendingAssertionIDs.isEmpty {
            await releaseSleepPendingAssertions(for: transitionToken)
        }

        guard !hasPendingAssertionCleanup else {
            let error = KeepAwakeError.assertionCleanupPending
            setState(.unavailable(error.localizedDescription))
            throw error
        }
    }

    private func scheduleSleepCleanup(for transitionToken: UUID) {
        guard sleepCleanupTask == nil else { return }
        let pendingRevision = sleepPendingRevision
        sleepCleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.releaseSleepPendingAssertions(for: transitionToken)
            guard self.sleepTransitionToken == transitionToken else { return }
            self.sleepCleanupTask = nil

            guard !self.sleepDidWake,
                  !self.sleepPendingAssertionIDs.isEmpty,
                  self.sleepPendingRevision != pendingRevision
            else { return }

            self.scheduleSleepCleanup(for: transitionToken)
        }
    }

    private func addSleepPendingAssertion(_ assertionID: IOPMAssertionID) {
        guard sleepPendingAssertionIDs.insert(assertionID).inserted else { return }
        sleepPendingRevision += 1
    }

    private func addSleepPendingAssertions(_ assertionIDs: [IOPMAssertionID]) {
        var didInsert = false
        for assertionID in assertionIDs {
            didInsert = sleepPendingAssertionIDs.insert(assertionID).inserted || didInsert
        }
        if didInsert {
            sleepPendingRevision += 1
        }
    }

    private func scheduleSleepCleanupIfNeeded() {
        guard let transitionToken = sleepTransitionToken else {
            let transitionToken = UUID()
            sleepTransitionToken = transitionToken
            sleepDidWake = true
            sleepReconciliationTask = Task { @MainActor [weak self] in
                await self?.reconcileSleepPendingAssertions(for: transitionToken)
            }
            return
        }

        if sleepDidWake {
            guard sleepReconciliationTask == nil else { return }
            sleepReconciliationTask = Task { @MainActor [weak self] in
                await self?.reconcileSleepPendingAssertions(for: transitionToken)
            }
        } else {
            scheduleSleepCleanup(for: transitionToken)
        }
    }

    private func releaseSleepPendingAssertions(for transitionToken: UUID) async {
        var firstError: KeepAwakeError?

        for assertionID in Array(sleepPendingAssertionIDs) {
            guard sleepTransitionToken == transitionToken, !sleepDidWake else { break }

            let error = await releaseAssertionWithRetry(
                assertionID,
                destination: .sleepTransition(transitionToken)
            ) { [weak self] in
                guard let self else { return false }
                return self.sleepTransitionToken == transitionToken && !self.sleepDidWake
            }

            guard sleepTransitionToken == transitionToken else { return }
            if sleepDidWake {
                break
            }

            if let error {
                firstError = firstError ?? error
            } else {
                sleepPendingAssertionIDs.remove(assertionID)
            }
        }

        if let firstError,
           sleepTransitionToken == transitionToken,
           !sleepDidWake
        {
            setState(.unavailable(firstError.localizedDescription))
        }

        if sleepPendingAssertionIDs.isEmpty, !sleepDidWake {
            finishSleepTransition(for: transitionToken)
        }
    }

    private func reconcileSleepPendingAssertions(for transitionToken: UUID) async {
        guard sleepTransitionToken == transitionToken else { return }

        var firstError: KeepAwakeError?
        while !sleepPendingAssertionIDs.isEmpty {
            for assertionID in Array(sleepPendingAssertionIDs) {
                if let releaseTask = inFlightReleaseTasks[assertionID] {
                    _ = await releaseTask.value
                }
                guard sleepTransitionToken == transitionToken else { return }

                let presence = await driver.reconcile(assertionID)
                guard sleepTransitionToken == transitionToken else { return }

                switch presence {
                case .owned:
                    if let error = await releaseAssertionWithRetry(
                        assertionID,
                        destination: .afterWake
                    ) {
                        firstError = firstError ?? error
                    }
                    sleepPendingAssertionIDs.remove(assertionID)
                case .missing, .notOwned:
                    sleepPendingAssertionIDs.remove(assertionID)
                }
            }
        }

        guard sleepTransitionToken == transitionToken else { return }
        sleepTransitionToken = nil
        sleepDidWake = false
        sleepCleanupTask = nil
        sleepReconciliationTask = nil

        if let firstError {
            setState(.unavailable(firstError.localizedDescription))
        } else if state.errorMessage != nil, !hasPendingAssertionCleanup {
            setState(.idle)
        }
    }

    private func finishSleepTransition(for transitionToken: UUID) {
        guard sleepTransitionToken == transitionToken,
              !sleepDidWake,
              sleepPendingAssertionIDs.isEmpty
        else { return }

        sleepTransitionToken = nil
        sleepDidWake = false
        sleepCleanupTask = nil
        if state.errorMessage != nil, !hasPendingAssertionCleanup {
            setState(.idle)
        }
    }

    private func releaseInBackground(
        _ assertionIDs: [IOPMAssertionID],
        operationToken: UUID,
        reportError: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !assertionIDs.isEmpty {
                _ = await self.releaseAssertions(
                    assertionIDs,
                    operationToken: operationToken,
                    reportError: reportError
                )
            }
            _ = await self.cleanupDriverPendingAssertions(
                operationToken: operationToken,
                reportError: reportError
            )
        }
    }

    private func releaseAssertions(
        _ assertionIDs: [IOPMAssertionID],
        operationToken: UUID,
        reportError: Bool
    ) async -> KeepAwakeError? {
        var firstError: KeepAwakeError?
        let releaseTasks = assertionIDs.map { assertionID in
            (assertionID, makeReleaseTask(for: assertionID, destination: .regular))
        }

        for (_, releaseTask) in releaseTasks {
            if let error = await releaseTask.value {
                firstError = firstError ?? error
            }
        }

        if reportError, let firstError, self.operationToken == operationToken {
            setState(.unavailable(firstError.localizedDescription))
        }
        return firstError
    }

    private func cleanupDriverPendingAssertions(
        operationToken: UUID,
        reportError: Bool
    ) async -> KeepAwakeError? {
        do {
            try await driver.cleanupPendingAssertions()
            return nil
        } catch {
            let keepAwakeError = normalizedReleaseError(error, assertionID: 0)
            if reportError, self.operationToken == operationToken {
                setState(.unavailable(keepAwakeError.localizedDescription))
            }
            return keepAwakeError
        }
    }

    private func releaseAssertionWithRetry(
        _ assertionID: IOPMAssertionID,
        destination: ReleaseFailureDestination = .regular,
        shouldContinue: (() -> Bool)? = nil
    ) async -> KeepAwakeError? {
        let task = makeReleaseTask(
            for: assertionID,
            destination: destination,
            shouldContinue: shouldContinue
        )
        return await task.value
    }

    private func makeReleaseTask(
        for assertionID: IOPMAssertionID,
        destination: ReleaseFailureDestination,
        shouldContinue: (() -> Bool)? = nil
    ) -> Task<KeepAwakeError?, Never> {
        if let task = inFlightReleaseTasks[assertionID] {
            return task
        }

        inFlightReleaseDestinations[assertionID] = destination
        let task: Task<KeepAwakeError?, Never> = Task { @MainActor [weak self] in
            guard let self else { return KeepAwakeError.assertionCleanupPending }
            let error = await self.performReleaseWithRetry(
                assertionID,
                shouldContinue: shouldContinue
            )
            self.completeRelease(assertionID, error: error)
            return error
        }
        inFlightReleaseTasks[assertionID] = task
        return task
    }

    private func performReleaseWithRetry(
        _ assertionID: IOPMAssertionID,
        shouldContinue: (() -> Bool)?
    ) async -> KeepAwakeError? {
        var lastError: KeepAwakeError?

        for attempt in 0...releaseRetryDelays.count {
            guard canContinueRelease(assertionID, explicitCondition: shouldContinue) else {
                return .assertionCleanupPending
            }

            do {
                try await driver.release(assertionID)
                return nil
            } catch {
                lastError = normalizedReleaseError(error, assertionID: assertionID)
            }

            guard attempt < releaseRetryDelays.count else { break }
            guard canContinueRelease(assertionID, explicitCondition: shouldContinue) else {
                break
            }
            do {
                try await sleepFor(releaseRetryDelays[attempt])
            } catch {
                break
            }
        }

        return lastError ?? .assertionCleanupPending
    }

    private func canContinueRelease(
        _ assertionID: IOPMAssertionID,
        explicitCondition: (() -> Bool)?
    ) -> Bool {
        if let explicitCondition, !explicitCondition() {
            return false
        }

        if case let .sleepTransition(transitionToken) = inFlightReleaseDestinations[assertionID] {
            return sleepTransitionToken == transitionToken && !sleepDidWake
        }
        return true
    }

    private func completeRelease(
        _ assertionID: IOPMAssertionID,
        error: KeepAwakeError?
    ) {
        let destination = inFlightReleaseDestinations.removeValue(forKey: assertionID) ?? .regular
        inFlightReleaseTasks[assertionID] = nil

        unreleasedAssertionIDs.remove(assertionID)
        guard error != nil else {
            sleepPendingAssertionIDs.remove(assertionID)
            return
        }

        switch destination {
        case .regular:
            if sleepPendingAssertionIDs.contains(assertionID) {
                return
            }
            unreleasedAssertionIDs.insert(assertionID)
        case .sleepTransition:
            addSleepPendingAssertion(assertionID)
        case .afterWake:
            sleepPendingAssertionIDs.remove(assertionID)
            unreleasedAssertionIDs.insert(assertionID)
        }
    }

    private func normalizedReleaseError(
        _ error: Error,
        assertionID: IOPMAssertionID
    ) -> KeepAwakeError {
        error as? KeepAwakeError
            ?? .assertionReleaseFailed(mode: nil, assertionID: assertionID, status: -1)
    }

    private func clearSessionMetadata() {
        expirationTask?.cancel()
        expirationTask = nil
        remainingTimeTask?.cancel()
        remainingTimeTask = nil
        expirationInstant = nil
        currentSession = nil
        remainingMinutes = nil
    }

    private func updateRemainingMinutes() {
        let newRemainingMinutes = calculateRemainingMinutes()
        guard remainingMinutes != newRemainingMinutes else { return }
        remainingMinutes = newRemainingMinutes
        onRemainingTimeChanged?(newRemainingMinutes)
    }

    private func setState(_ state: KeepAwakeState) {
        guard self.state != state else { return }
        self.state = state
        onStateChanged?(state)
    }

    private func remainingSeconds(until deadline: ContinuousClock.Instant) -> Int? {
        let remaining = deadline - now()
        guard remaining > .zero else { return 0 }

        let components = remaining.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return Int(ceil(seconds))
    }

    private func calculateRemainingMinutes() -> Int? {
        guard let expirationInstant,
              let remainingSeconds = remainingSeconds(until: expirationInstant)
        else { return nil }
        guard remainingSeconds > 0 else { return 0 }
        return max(1, (remainingSeconds + 59) / 60)
    }
}
