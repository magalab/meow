import Darwin
import Foundation

public actor SystemMetricsActor {
    private var configuration: SystemMonitorConfiguration
    private var samplingTask: Task<Void, Never>?
    private var onSnapshot: (@Sendable @MainActor (SystemMetricsSnapshot) -> Void)?
    private var lastSampleDate: Date?

    private var cpu = CPUMetricCollector()
    private var memory = MemoryMetricCollector()
    private var gpu = GPUMetricCollector()
    private var network = NetworkMetricCollector()
    private var disk = DiskMetricCollector()
    private var power = PowerMetricCollector()
    private var thermal = ThermalMetricCollector()
    private var networkAddresses = NetworkAddressCollector()
    private var publicIPAddress: String?
    private var publicIPFetchInFlight = false
    private var nextPublicIPRefreshDate: Date?
    private var publicIPRetryAttempt = 0

    public init(configuration: SystemMonitorConfiguration = .init()) {
        self.configuration = configuration
    }

    public func start(
        onSnapshot: @escaping @Sendable @MainActor (SystemMetricsSnapshot) -> Void
    ) {
        self.onSnapshot = onSnapshot
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        onSnapshot = nil
        lastSampleDate = nil
        cpu = CPUMetricCollector()
        memory = MemoryMetricCollector()
        gpu = GPUMetricCollector()
        network = NetworkMetricCollector()
        disk = DiskMetricCollector()
        power = PowerMetricCollector()
        thermal = ThermalMetricCollector()
        networkAddresses = NetworkAddressCollector()
        publicIPAddress = nil
        publicIPFetchInFlight = false
        nextPublicIPRefreshDate = nil
        publicIPRetryAttempt = 0
    }

    public func update(configuration: SystemMonitorConfiguration) {
        self.configuration = configuration
    }

    public func sampleNow() async {
        await emit(sample())
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await emit(sample())
            let nanoseconds = UInt64(max(1, configuration.updateInterval) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
        }
    }

    private func sample() -> SystemMetricsSnapshot {
        let now = Date()
        let elapsed = lastSampleDate.map { max(0.001, now.timeIntervalSince($0)) } ?? 0
        lastSampleDate = now
        let modules = configuration.enabledModules
        var snapshot = SystemMetricsSnapshot(capturedAt: now)

        if modules.contains(.cpu) {
            snapshot.cpuUsage = cpu.sample()
        }
        if modules.contains(.memory), let value = memory.sample() {
            snapshot.memoryUsedFraction = value.used
            snapshot.memoryPressureFraction = value.pressure
            snapshot.memoryPressureSource = value.pressureSource
        }
        if modules.contains(.gpu), let value = gpu.sample() {
            snapshot.gpuUsageFraction = value.usage
            snapshot.gpuMemoryUsedBytes = value.used
            snapshot.gpuMemoryTotalBytes = value.total
        }
        if modules.contains(.network), let value = network.sample(elapsed: elapsed) {
            snapshot.networkDownloadBytesPerSecond = value.download
            snapshot.networkUploadBytesPerSecond = value.upload
        }
        if modules.contains(.network) {
            snapshot.localIPAddresses = networkAddresses.sample()
            snapshot.publicIPAddress = publicIPAddress
            refreshPublicIPAddressIfNeeded(at: now)
        }
        if modules.contains(.disk), let value = disk.sample(elapsed: elapsed) {
            snapshot.diskUsedFraction = value.used
            snapshot.diskReadBytesPerSecond = value.read
            snapshot.diskWriteBytesPerSecond = value.write
        }
        if modules.contains(.power) {
            let value = power.sample()
            snapshot.batteryFraction = value.fraction
            snapshot.batteryIsCharging = value.charging
        }
        if modules.contains(.thermal) {
            snapshot.thermalPressure = thermal.sample()
        }
        return snapshot
    }

    private func emit(_ snapshot: SystemMetricsSnapshot) async {
        guard let onSnapshot else { return }
        await onSnapshot(snapshot)
    }

    private func refreshPublicIPAddressIfNeeded(at date: Date) {
        let shouldRefresh = nextPublicIPRefreshDate.map { date >= $0 } ?? true
        guard shouldRefresh, !publicIPFetchInFlight else { return }
        publicIPFetchInFlight = true
        Task { [weak self] in
            let address = await Self.fetchPublicIPAddress()
            await self?.receivePublicIPAddress(address, at: Date())
        }
    }

    private func receivePublicIPAddress(_ address: String?, at date: Date) {
        if let address {
            publicIPAddress = address
            publicIPRetryAttempt = 0
            nextPublicIPRefreshDate = date.addingTimeInterval(600)
        } else {
            publicIPRetryAttempt = min(publicIPRetryAttempt + 1, 5)
            let multiplier = 1 << max(0, publicIPRetryAttempt - 1)
            let retryDelay = min(600, TimeInterval(30 * multiplier))
            nextPublicIPRefreshDate = date.addingTimeInterval(retryDelay)
        }
        publicIPFetchInFlight = false
    }

    private static func fetchPublicIPAddress() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let address = String(data: data, encoding: .utf8)
        else { return nil }
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return isIPv4Address(normalized) ? normalized : nil
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &address) == 1
        }
    }
}
