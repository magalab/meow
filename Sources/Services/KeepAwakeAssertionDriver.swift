import Foundation
import IOKit.pwr_mgt
import os

@MainActor
protocol KeepAwakeAsserting: AnyObject {
    func acquire(for mode: KeepAwakeMode) async throws -> IOPMAssertionID
    func release(_ assertionID: IOPMAssertionID) async throws
    func reconcile(_ assertionID: IOPMAssertionID) async -> KeepAwakeAssertionPresence
    func cleanupPendingAssertions() async throws
    func systemWillSleep()
    func systemDidWake()
}

enum KeepAwakeAssertionPresence: Sendable, Equatable {
    /// The assertion still exists with the expected Meow name and type.
    case owned

    /// The power manager no longer reports this assertion ID.
    case missing

    /// The ID exists, but it no longer identifies this Meow assertion.
    case notOwned
}

extension KeepAwakeAsserting {
    func reconcile(_: IOPMAssertionID) async -> KeepAwakeAssertionPresence {
        .owned
    }

    func cleanupPendingAssertions() async throws {}

    func systemWillSleep() {}

    func systemDidWake() {}
}

enum KeepAwakeError: LocalizedError, Equatable, Sendable {
    case disabled
    case assertionCleanupPending
    case invalidAssertionID(mode: KeepAwakeMode)
    case assertionCreateFailed(mode: KeepAwakeMode, status: Int32)
    case assertionReleaseFailed(mode: KeepAwakeMode?, assertionID: IOPMAssertionID, status: Int32)
    case assertionRollbackFailed(assertionID: IOPMAssertionID, status: Int32)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return L10n.keepAwakeErrorDisabled
        case .assertionCleanupPending:
            return L10n.keepAwakeErrorCleanupPending
        case let .invalidAssertionID(mode):
            return L10n.keepAwakeErrorInvalidAssertionID(mode: mode.displayName)
        case let .assertionCreateFailed(mode, status):
            return L10n.keepAwakeErrorAssertionCreateFailed(
                mode: mode.displayName,
                status: String(status)
            )
        case let .assertionReleaseFailed(mode, assertionID, status):
            return L10n.keepAwakeErrorAssertionReleaseFailed(
                assertionID: String(assertionID),
                mode: mode?.displayName,
                status: String(status)
            )
        case let .assertionRollbackFailed(assertionID, status):
            return L10n.keepAwakeErrorAssertionRollbackFailed(
                assertionID: String(assertionID),
                status: String(status)
            )
        }
    }

    var statusCode: Int32? {
        switch self {
        case let .assertionCreateFailed(_, status),
             let .assertionReleaseFailed(_, _, status),
             let .assertionRollbackFailed(_, status):
            return status
        case .disabled, .assertionCleanupPending, .invalidAssertionID:
            return nil
        }
    }
}

@MainActor
final class IOKitKeepAwakeAssertionDriver: KeepAwakeAsserting {
    private struct OperationResult: Sendable {
        let status: IOReturn
        let assertionID: IOPMAssertionID
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "tech.lury.meow",
        category: "keepAwake"
    )
    private var modesByAssertionID: [IOPMAssertionID: KeepAwakeMode] = [:]
    private var pendingRollbackAssertionIDs = Set<IOPMAssertionID>()
    private var pendingRollbackInFlightAssertionIDs = Set<IOPMAssertionID>()
    private var sleepPendingRollbackAssertionIDs = Set<IOPMAssertionID>()
    private var pendingRollbackCleanupTask: Task<KeepAwakeError?, Never>?
    private var pendingRollbackWakeTask: Task<Void, Never>?
    private var sleepGeneration = 0
    private var sleepTransitionActive = false
    private var sleepDidWake = false

    func acquire(for mode: KeepAwakeMode) async throws -> IOPMAssertionID {
        try await cleanupPendingAssertions()

        let assertionName = "\(BuildEdition.productName) Keep Awake"
        let result = await Task.detached(priority: .userInitiated) {
            var assertionID: IOPMAssertionID = 0
            let status: IOReturn

            switch mode {
            case .system:
                status = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    assertionName as CFString,
                    &assertionID
                )
            case .display:
                status = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    assertionName as CFString,
                    &assertionID
                )
            }

            return OperationResult(status: status, assertionID: assertionID)
        }.value

        logger.info(
            "acquire mode=\(mode.rawValue, privacy: .public) id=\(result.assertionID, privacy: .public) return=\(result.status, privacy: .public)"
        )

        if result.assertionID != 0 {
            modesByAssertionID[result.assertionID] = mode
        }

        if Task.isCancelled {
            if result.assertionID != 0 {
                try await rollback(assertionID: result.assertionID)
            }
            throw CancellationError()
        }

        guard result.status == kIOReturnSuccess else {
            if result.assertionID != 0 {
                try await rollback(assertionID: result.assertionID)
            }
            throw KeepAwakeError.assertionCreateFailed(mode: mode, status: Int32(result.status))
        }
        guard result.assertionID != 0 else {
            throw KeepAwakeError.invalidAssertionID(mode: mode)
        }
        return result.assertionID
    }

    func release(_ assertionID: IOPMAssertionID) async throws {
        try await releaseAssertion(assertionID, clearTrackingOnSuccess: true)
    }

    private func releaseAssertion(
        _ assertionID: IOPMAssertionID,
        clearTrackingOnSuccess: Bool
    ) async throws {
        guard assertionID != 0 else { return }

        let mode = modesByAssertionID[assertionID]

        let status = await Task.detached(priority: .userInitiated) {
            IOPMAssertionRelease(assertionID)
        }.value

        logger.info(
            "release mode=\(mode?.rawValue ?? "unknown", privacy: .public) id=\(assertionID, privacy: .public) return=\(status, privacy: .public)"
        )

        guard status == kIOReturnSuccess else {
            throw KeepAwakeError.assertionReleaseFailed(
                mode: mode,
                assertionID: assertionID,
                status: Int32(status)
            )
        }
        if clearTrackingOnSuccess {
            forgetAssertion(assertionID)
        }
    }

    func cleanupPendingAssertions() async throws {
        if let wakeTask = pendingRollbackWakeTask {
            _ = await wakeTask.value
        }

        if let cleanupTask = pendingRollbackCleanupTask {
            if let error = await cleanupTask.value {
                throw error
            }
            return
        }

        let cleanupTask: Task<KeepAwakeError?, Never> = Task { @MainActor [weak self] in
            guard let self else { return .assertionCleanupPending }
            return await self.performPendingRollbackCleanup()
        }
        pendingRollbackCleanupTask = cleanupTask
        let error = await cleanupTask.value
        pendingRollbackCleanupTask = nil

        if let error {
            throw error
        }
    }

    func systemWillSleep() {
        sleepGeneration += 1
        sleepTransitionActive = true
        sleepDidWake = false
        sleepPendingRollbackAssertionIDs.formUnion(pendingRollbackAssertionIDs)
        sleepPendingRollbackAssertionIDs.formUnion(pendingRollbackInFlightAssertionIDs)
        logger.info("system will sleep generation=\(self.sleepGeneration, privacy: .public)")
    }

    func systemDidWake() {
        guard !sleepDidWake else { return }
        sleepDidWake = true
        let generation = sleepGeneration
        let cleanupTask = pendingRollbackCleanupTask
        pendingRollbackWakeTask = Task { @MainActor [weak self, cleanupTask] in
            _ = await cleanupTask?.value
            guard let self else { return }
            await self.reconcilePendingRollbackAssertions(afterWakeGeneration: generation)
            guard self.sleepGeneration == generation else { return }
            self.sleepDidWake = false
            self.sleepTransitionActive = false
        }
    }

    private func performPendingRollbackCleanup() async -> KeepAwakeError? {
        var firstError: Error?
        var cleanupDeferred = false

        let assertionIDs = pendingRollbackAssertionIDs.union(sleepPendingRollbackAssertionIDs)
        for assertionID in Array(assertionIDs) {
            pendingRollbackInFlightAssertionIDs.insert(assertionID)
            defer { pendingRollbackInFlightAssertionIDs.remove(assertionID) }

            let operationGeneration = sleepGeneration
            switch await reconcile(assertionID) {
            case .owned:
                guard sleepGeneration == operationGeneration, !sleepTransitionActive else {
                    sleepPendingRollbackAssertionIDs.insert(assertionID)
                    cleanupDeferred = true
                    continue
                }
                do {
                    try await releaseAssertion(assertionID, clearTrackingOnSuccess: false)
                    if sleepGeneration == operationGeneration, !sleepTransitionActive {
                        forgetAssertion(assertionID)
                    } else {
                        sleepPendingRollbackAssertionIDs.insert(assertionID)
                    }
                } catch {
                    firstError = firstError ?? error
                }
            case .missing, .notOwned:
                // The power manager removed or reassigned the ID. Forget it
                // without calling IOPMAssertionRelease on a reused handle.
                forgetAssertion(assertionID)
            }
        }

        if let firstError {
            return normalizedKeepAwakeError(firstError, assertionID: 0)
        }
        if cleanupDeferred {
            return .assertionCleanupPending
        }
        return nil
    }

    private func reconcilePendingRollbackAssertions(afterWakeGeneration generation: Int) async {
        guard sleepGeneration == generation, sleepDidWake else { return }

        var firstError: KeepAwakeError?
        let assertionIDs = sleepPendingRollbackAssertionIDs
            .union(pendingRollbackAssertionIDs)
            .union(pendingRollbackInFlightAssertionIDs)
        for assertionID in Array(assertionIDs) {
            guard sleepGeneration == generation, sleepDidWake else { return }

            pendingRollbackInFlightAssertionIDs.insert(assertionID)
            defer { pendingRollbackInFlightAssertionIDs.remove(assertionID) }
            switch await reconcile(assertionID) {
            case .owned:
                guard sleepGeneration == generation, sleepDidWake else { return }
                do {
                    try await releaseAssertion(assertionID, clearTrackingOnSuccess: false)
                    forgetAssertion(assertionID)
                } catch {
                    firstError = firstError ?? normalizedKeepAwakeError(error, assertionID: assertionID)
                }
            case .missing, .notOwned:
                forgetAssertion(assertionID)
            }
        }

        if let firstError {
            logger.error(
                "wake cleanup failed error=\(firstError.localizedDescription, privacy: .public)"
            )
        }
    }

    private func normalizedKeepAwakeError(
        _ error: Error,
        assertionID: IOPMAssertionID
    ) -> KeepAwakeError {
        error as? KeepAwakeError
            ?? .assertionReleaseFailed(mode: nil, assertionID: assertionID, status: -1)
    }

    func reconcile(_ assertionID: IOPMAssertionID) async -> KeepAwakeAssertionPresence {
        guard assertionID != 0,
              let mode = modesByAssertionID[assertionID]
        else {
            return .missing
        }

        let expectedName = "\(BuildEdition.productName) Keep Awake"
        let expectedType = assertionType(for: mode)
        let inspection = await Task.detached(priority: .utility) {
            guard let unmanagedProperties = IOPMAssertionCopyProperties(assertionID) else {
                return AssertionInspection(name: nil, type: nil)
            }

            let properties = unmanagedProperties.takeRetainedValue()
            let dictionary = properties as NSDictionary
            return AssertionInspection(
                name: dictionary[kIOPMAssertionNameKey as String] as? String,
                type: dictionary[kIOPMAssertionTypeKey as String] as? String
            )
        }.value

        guard let name = inspection.name,
              let type = inspection.type
        else {
            forgetAssertion(assertionID)
            return .missing
        }

        guard name == expectedName, type == expectedType else {
            forgetAssertion(assertionID)
            return .notOwned
        }
        return .owned
    }

    private func rollback(assertionID: IOPMAssertionID) async throws {
        do {
            try await release(assertionID)
        } catch {
            pendingRollbackAssertionIDs.insert(assertionID)
            let status = (error as? KeepAwakeError)?.statusCode ?? -1
            logger.error(
                "rollback release failed id=\(assertionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw KeepAwakeError.assertionRollbackFailed(assertionID: assertionID, status: status)
        }
    }

    private func forgetAssertion(_ assertionID: IOPMAssertionID) {
        modesByAssertionID.removeValue(forKey: assertionID)
        pendingRollbackAssertionIDs.remove(assertionID)
        sleepPendingRollbackAssertionIDs.remove(assertionID)
    }

    private func assertionType(for mode: KeepAwakeMode) -> String {
        switch mode {
        case .system:
            return kIOPMAssertionTypePreventUserIdleSystemSleep as String
        case .display:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }
    }

    private struct AssertionInspection: Sendable {
        let name: String?
        let type: String?
    }
}
