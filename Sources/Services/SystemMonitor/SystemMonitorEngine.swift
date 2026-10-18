import Combine
import Foundation

@MainActor
public final class SystemMonitorEngine: ObservableObject {
    @Published public private(set) var snapshot: SystemMetricsSnapshot?
    @Published public private(set) var history: SystemMetricsHistory
    @Published public private(set) var isRunning = false
    public var onSnapshot: ((SystemMetricsSnapshot) -> Void)?

    private var configuration: SystemMonitorConfiguration
    private var sampler: SystemMetricsActor?
    private var samplerLifecycleTask: Task<Void, Never>?
    private var samplerGeneration: UInt64 = 0

    public init(configuration: SystemMonitorConfiguration = .init()) {
        self.configuration = configuration
        self.history = SystemMetricsHistory(capacity: configuration.historyCapacity)
    }

    public func start() {
        guard sampler == nil else { return }
        let sampler = SystemMetricsActor(configuration: configuration)
        self.sampler = sampler
        samplerGeneration &+= 1
        let generation = samplerGeneration
        let previousLifecycleTask = samplerLifecycleTask
        isRunning = true
        let callback: @Sendable @MainActor (SystemMetricsSnapshot) -> Void = { [weak self] snapshot in
            self?.ingest(snapshot, generation: generation)
        }
        samplerLifecycleTask = Task { [weak self] in
            await previousLifecycleTask?.value
            await sampler.start(onSnapshot: callback)
            guard let self,
                  self.samplerGeneration == generation,
                  self.sampler === sampler
            else {
                await sampler.stop()
                return
            }
        }
    }

    public func stop(clearData: Bool = true) {
        guard let sampler else {
            isRunning = false
            if clearData {
                snapshot = nil
                history.removeAll()
            }
            return
        }
        self.sampler = nil
        samplerGeneration &+= 1
        isRunning = false
        if clearData {
            snapshot = nil
            history.removeAll()
        }
        let previousLifecycleTask = samplerLifecycleTask
        samplerLifecycleTask = Task {
            await previousLifecycleTask?.value
            await sampler.stop()
        }
    }

    public func update(configuration: SystemMonitorConfiguration) {
        self.configuration = configuration
        history.resize(to: configuration.historyCapacity)
        guard let sampler else { return }
        let lifecycleTask = samplerLifecycleTask
        Task {
            await lifecycleTask?.value
            await sampler.update(configuration: configuration)
        }
    }

    public func refreshNow() {
        guard let sampler else { return }
        let lifecycleTask = samplerLifecycleTask
        Task {
            await lifecycleTask?.value
            await sampler.sampleNow()
        }
    }

    private func ingest(_ snapshot: SystemMetricsSnapshot, generation: UInt64) {
        guard samplerGeneration == generation, sampler != nil else { return }
        self.snapshot = snapshot
        history.append(snapshot)
        onSnapshot?(snapshot)
    }
}
