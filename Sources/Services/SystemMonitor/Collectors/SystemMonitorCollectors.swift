import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.storage
import Metal

struct CPUMetricCollector {
    private var previousTicks: [UInt32] = []

    mutating func sample() -> Double? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &coreCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info, coreCount > 0 else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            )
        }

        let stateCount = Int(CPU_STATE_MAX)
        let count = Int(coreCount) * stateCount
        var current = [UInt32](repeating: 0, count: count)
        for index in 0..<min(count, Int(infoCount)) {
            current[index] = UInt32(bitPattern: info[index])
        }

        guard previousTicks.count == current.count else {
            previousTicks = current
            return nil
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for core in 0..<Int(coreCount) {
            let base = core * stateCount
            let user = UInt64(current[base + Int(CPU_STATE_USER)] &- previousTicks[base + Int(CPU_STATE_USER)])
            let system = UInt64(current[base + Int(CPU_STATE_SYSTEM)] &- previousTicks[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(current[base + Int(CPU_STATE_IDLE)] &- previousTicks[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(current[base + Int(CPU_STATE_NICE)] &- previousTicks[base + Int(CPU_STATE_NICE)])
            busy += user + system + nice
            total += user + system + idle + nice
        }
        previousTicks = current
        guard total > 0 else { return nil }
        return min(1, max(0, Double(busy) / Double(total)))
    }
}

struct MemoryMetricCollector {
    mutating func sample() -> (
        used: Double,
        pressure: Double,
        pressureSource: SystemMemoryPressureSource
    )? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var hostPageSize: vm_size_t = 0
        let pageHost = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, pageHost) }
        guard host_page_size(pageHost, &hostPageSize) == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }

        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * pageSize

        var pressureLevel: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &pressureLevel,
            &pressureSize,
            nil,
            0
        )
        let pressure: Double
        let pressureSource: SystemMemoryPressureSource
        if pressureResult == 0 {
            // This sysctl is not a documented macOS public API. Its values are
            // treated as a best-effort heuristic and exposed with their source.
            switch pressureLevel {
            case 4: pressure = 1
            case 2: pressure = 0.66
            default: pressure = 0.25
            }
            pressureSource = .systemPressureLevel
        } else {
            pressure = min(1, max(0, Double(usedBytes) / Double(total)))
            pressureSource = .usedMemoryRatioFallback
        }

        return (
            min(1, max(0, Double(usedBytes) / Double(total))),
            pressure,
            pressureSource
        )
    }
}

private enum NetworkInterfaceFilter {
    static func isPhysicalInterface(_ name: String) -> Bool {
        // macOS physical Ethernet and Wi-Fi interfaces use the en* namespace.
        // This excludes loopback, VPN (utun/ipsec), bridge, and hypervisor
        // interfaces from both traffic and address metrics.
        name.hasPrefix("en")
    }
}

struct NetworkMetricCollector {
    private var previousInput: UInt64?
    private var previousOutput: UInt64?

    mutating func sample(elapsed: TimeInterval) -> (download: Double, upload: Double)? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(first) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let flags = interface.pointee.ifa_flags
            let name = String(cString: interface.pointee.ifa_name)
            if NetworkInterfaceFilter.isPhysicalInterface(name), flags & UInt32(IFF_UP) != 0,
               let dataPointer = interface.pointee.ifa_data
            {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                input += UInt64(data.ifi_ibytes)
                output += UInt64(data.ifi_obytes)
            }
            current = interface.pointee.ifa_next
        }

        defer {
            previousInput = input
            previousOutput = output
        }
        guard let previousInput, let previousOutput, elapsed > 0 else { return nil }
        let inputDelta = input >= previousInput ? input - previousInput : 0
        let outputDelta = output >= previousOutput ? output - previousOutput : 0
        return (
            Double(inputDelta) / elapsed,
            Double(outputDelta) / elapsed
        )
    }
}

struct NetworkAddressCollector {
    func sample() -> [String] {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return [] }
        defer { freeifaddrs(first) }

        var addresses: [(interface: String, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let name = String(cString: interface.pointee.ifa_name)
            let flags = interface.pointee.ifa_flags
            guard NetworkInterfaceFilter.isPhysicalInterface(name),
                  flags & UInt32(IFF_UP) != 0,
                  let address = interface.pointee.ifa_addr
            else {
                current = interface.pointee.ifa_next
                continue
            }

            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) else {
                current = interface.pointee.ifa_next
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let end = host.firstIndex(of: 0) ?? host.endIndex
                let bytes = host[..<end].map { UInt8(bitPattern: $0) }
                let value = String(decoding: bytes, as: UTF8.self)
                addresses.append((name, value))
            }
            current = interface.pointee.ifa_next
        }

        return addresses
            .sorted { lhs, rhs in
                interfacePriority(lhs.interface) < interfacePriority(rhs.interface)
            }
            .map(\.address)
            .reduce(into: []) { result, address in
                if !result.contains(address) {
                    result.append(address)
                }
            }
    }

    private func interfacePriority(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name == "en1" { return 1 }
        if name.hasPrefix("en") { return 2 }
        return 3
    }
}

struct DiskMetricCollector {
    private var previousRead: UInt64?
    private var previousWrite: UInt64?

    mutating func sample(elapsed: TimeInterval) -> (used: Double, read: Double?, write: Double?)? {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        let available = max(0, values.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = min(1, max(0, 1 - Double(available) / Double(total)))

        var iterator: io_iterator_t = IO_OBJECT_NULL
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOBlockStorageDriverClass),
            &iterator
        )
        guard matchResult == KERN_SUCCESS else { return (used, nil, nil) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(
                service,
                kIOBlockStorageDriverStatisticsKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            read += (property[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber)?.uint64Value ?? 0
            write += (property[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber)?.uint64Value ?? 0
        }

        defer {
            previousRead = read
            previousWrite = write
        }
        guard let previousRead, let previousWrite, elapsed > 0 else {
            return (used, nil, nil)
        }
        let readDelta = read >= previousRead ? read - previousRead : 0
        let writeDelta = write >= previousWrite ? write - previousWrite : 0
        return (
            used,
            Double(readDelta) / elapsed,
            Double(writeDelta) / elapsed
        )
    }
}

struct PowerMetricCollector {
    mutating func sample() -> (fraction: Double?, charging: Bool?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return (nil, nil)
        }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let fraction = maximum.map { max(0, min(1, (current ?? 0) / max($0, 1))) }
            let charging = description[kIOPSIsChargingKey] as? Bool
            return (fraction, charging)
        }
        return (nil, nil)
    }
}

struct GPUMetricCollector {
    mutating func sample() -> (usage: Double?, used: UInt64?, total: UInt64?)? {
        guard let device = MTLCopyAllDevices().first else { return nil }
        let total = device.recommendedMaxWorkingSetSize
        var usage: Double?
        var used: UInt64?
        if let matching = IORegistryEntryIDMatching(device.registryID) {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            if service != IO_OBJECT_NULL {
                defer { IOObjectRelease(service) }
                if let property = IORegistryEntryCreateCFProperty(
                    service,
                    "PerformanceStatistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any]
                {
                    let utilizationKeys = [
                        "Device Utilization %",
                        "Device Utilization",
                        "GPU Activity(%)",
                        "GPU Core Utilization"
                    ]
                    for key in utilizationKeys {
                        if let value = property[key] as? NSNumber {
                            usage = min(1, max(0, value.doubleValue / 100))
                            break
                        }
                    }
                    let memoryKeys = [
                        "In use system memory",
                        "vramUsedBytes",
                        "gartUsedBytes",
                        "Alloc system memory"
                    ]
                    for key in memoryKeys {
                        if let value = property[key] as? NSNumber, value.doubleValue >= 0 {
                            used = UInt64(value.doubleValue)
                            break
                        }
                    }
                }
            }
        }
        guard usage != nil || used != nil || total > 0 else { return nil }
        return (usage, used, total > 0 ? total : nil)
    }
}

struct ThermalMetricCollector {
    mutating func sample() -> SystemThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}
