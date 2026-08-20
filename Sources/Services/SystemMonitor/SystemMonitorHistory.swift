import Foundation

public struct SystemMetricsHistory: Sendable, Equatable {
    public private(set) var samples: [SystemMetricsSnapshot] = []
    public private(set) var capacity: Int

    public init(capacity: Int = 150) {
        self.capacity = max(30, capacity)
    }

    public mutating func resize(to newCapacity: Int) {
        capacity = max(30, newCapacity)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public mutating func append(_ sample: SystemMetricsSnapshot) {
        if samples.count >= capacity {
            samples.removeFirst()
        }
        samples.append(sample)
    }

    public mutating func removeAll() {
        samples.removeAll(keepingCapacity: true)
    }
}
