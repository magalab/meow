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

    public init(configuration: SystemMonitorConfiguration = .init()) {
        self.configuration = configuration
        self.history = SystemMetricsHistory(capacity: configuration.historyCapacity)
    }

    public func start() {
        guard sampler == nil else { return }
        let sampler = SystemMetricsActor(configuration: configuration)
        self.sampler = sampler
        isRunning = true
        let callback: @Sendable @MainActor (SystemMetricsSnapshot) -> Void = { [weak self] snapshot in
            self?.ingest(snapshot)
        }
        Task { await sampler.start(onSnapshot: callback) }
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
        isRunning = false
        if clearData {
            snapshot = nil
            history.removeAll()
        }
        Task { await sampler.stop() }
    }

    public func update(configuration: SystemMonitorConfiguration) {
        self.configuration = configuration
        history.resize(to: configuration.historyCapacity)
        guard let sampler else { return }
        Task { await sampler.update(configuration: configuration) }
    }

    public func refreshNow() {
        guard let sampler else { return }
        Task { await sampler.sampleNow() }
    }

    private func ingest(_ snapshot: SystemMetricsSnapshot) {
        self.snapshot = snapshot
        history.append(snapshot)
        onSnapshot?(snapshot)
    }
}
