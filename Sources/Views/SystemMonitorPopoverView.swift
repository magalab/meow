import AppKit
import SwiftUI

struct SystemMonitorPopoverView: View {
    @ObservedObject var engine: SystemMonitorEngine
    let theme: AppTheme
    let enabledModules: Set<SystemMonitorModule>
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedValue: String?

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                header
                metricGrid
                if enabledModules.contains(.network) {
                    addressSection
                }
                if enabledModules.contains(.cpu) || enabledModules.contains(.memory) {
                    recentSummary
                }
            }
            .padding(10)
        }
        .frame(width: 350)
        .frame(maxHeight: 560)
        .background(
            LinearGradient(
                colors: palette.preferencesGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .id(lang.refreshToken)
        .task(id: copiedValue) {
            guard copiedValue != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copiedValue = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 28, height: 28)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.systemMonitorTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(lastUpdatedText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                engine.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.systemMonitorRefresh)
        }
    }

    @ViewBuilder
    private var metricGrid: some View {
        let modules = SystemMonitorModule.allCases.filter { enabledModules.contains($0) }
        if modules.count == 1, let module = modules.first {
            HStack {
                metricCard(for: module)
                    .frame(width: 140)
                Spacer(minLength: 0)
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(modules, id: \.self) { module in
                    metricCard(for: module)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCard(for module: SystemMonitorModule) -> some View {
        switch module {
        case .cpu:
            metricCard(title: L10n.systemMonitorCPU, symbol: "cpu", value: percentage(engine.snapshot?.cpuUsage), detail: L10n.systemMonitorUsage)
        case .memory:
            metricCard(title: L10n.systemMonitorMemory, symbol: "memorychip", value: percentage(engine.snapshot?.memoryUsedFraction), detail: pressureDetail)
        case .network:
            metricCard(title: L10n.systemMonitorNetwork, symbol: "arrow.up.arrow.down", value: networkValue, detail: networkDetail)
        case .disk:
            metricCard(title: L10n.systemMonitorDisk, symbol: "internaldrive", value: percentage(engine.snapshot?.diskUsedFraction), detail: diskDetail)
        case .gpu:
            metricCard(title: L10n.systemMonitorGPU, symbol: "sparkles", value: gpuValue, detail: gpuDetail)
        case .power:
            metricCard(title: L10n.systemMonitorPower, symbol: "battery.75percent", value: percentage(engine.snapshot?.batteryFraction), detail: powerDetail)
        case .thermal:
            metricCard(title: L10n.systemMonitorThermal, symbol: "thermometer.medium", value: thermalValue, detail: "")
        }
    }

    private var addressSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n.systemMonitorAddress)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            addressValue(
                title: L10n.systemMonitorLocalIP,
                value: localIPValue,
                copyValue: engine.snapshot?.localIPAddresses?.joined(separator: ", ")
            )
            addressValue(
                title: L10n.systemMonitorPublicIP,
                value: publicIPValue,
                copyValue: engine.snapshot?.publicIPAddress
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func addressValue(title: String, value: String, copyValue: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Button {
                    guard let copyValue else { return }
                    copyToPasteboard(copyValue)
                } label: {
                    Image(systemName: copiedValue == copyValue ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            (copiedValue == copyValue ? Color.green : Color.secondary).opacity(0.12),
                            in: Circle()
                        )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copiedValue == copyValue ? Color.green : Color.secondary)
                .disabled(copyValue == nil)
                .help(copiedValue == copyValue ? L10n.systemMonitorCopied : L10n.systemMonitorCopyIP)
                .accessibilityLabel(copiedValue == copyValue ? L10n.systemMonitorCopied : L10n.systemMonitorCopyIP)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedValue = value
    }

    @ViewBuilder
    private var recentSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(L10n.systemMonitorHistory)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 4) {
                if enabledModules.contains(.cpu) {
                    summaryRow(title: L10n.systemMonitorCPU, samples: engine.history.samples.compactMap(\.cpuUsage))
                }
                if enabledModules.contains(.memory) {
                    summaryRow(title: L10n.systemMonitorMemory, samples: engine.history.samples.compactMap(\.memoryUsedFraction))
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func summaryRow(title: String, samples: [Double]) -> some View {
        let average = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
        let peak = samples.max()
        return HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Text(summaryValue(average: average, peak: peak))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func metricCard(title: String, symbol: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !detail.isEmpty {
                    Spacer(minLength: 2)
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 62, alignment: .leading)
        .padding(.horizontal, 9)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private var lastUpdatedText: String {
        guard let date = engine.snapshot?.capturedAt else { return L10n.systemMonitorWaiting }
        return String(format: L10n.systemMonitorUpdated, date.formatted(date: .omitted, time: .standard))
    }

    private var pressureDetail: String {
        guard let pressure = engine.snapshot?.memoryPressureFraction else { return L10n.systemMonitorUnavailable }
        return String(format: L10n.systemMonitorPressure, pressure * 100)
    }

    private var networkValue: String {
        guard let value = engine.snapshot?.networkDownloadBytesPerSecond else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
    }

    private var networkDetail: String {
        guard let value = engine.snapshot?.networkUploadBytesPerSecond else { return L10n.systemMonitorUnavailable }
        return "↑ \(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary))/s"
    }

    private var diskDetail: String {
        guard let read = engine.snapshot?.diskReadBytesPerSecond,
              let write = engine.snapshot?.diskWriteBytesPerSecond
        else { return L10n.systemMonitorDiskUsage }
        return "R \(formatRate(read)) · W \(formatRate(write))"
    }

    private var gpuValue: String {
        if let usage = engine.snapshot?.gpuUsageFraction {
            return percentage(usage)
        }
        guard let used = engine.snapshot?.gpuMemoryUsedBytes,
              let total = engine.snapshot?.gpuMemoryTotalBytes,
              total > 0
        else { return L10n.systemMonitorUnavailable }
        return percentage(Double(used) / Double(total))
    }

    private var gpuDetail: String {
        guard let used = engine.snapshot?.gpuMemoryUsedBytes,
              let total = engine.snapshot?.gpuMemoryTotalBytes,
              total > 0
        else { return L10n.systemMonitorUnavailable }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .binary))"
    }

    private var powerDetail: String {
        guard let charging = engine.snapshot?.batteryIsCharging else { return L10n.systemMonitorNoBattery }
        return charging ? L10n.systemMonitorCharging : L10n.systemMonitorDischarging
    }

    private var thermalValue: String {
        switch engine.snapshot?.thermalPressure {
        case .nominal: return L10n.systemMonitorThermalNominal
        case .fair: return L10n.systemMonitorThermalFair
        case .serious: return L10n.systemMonitorThermalSerious
        case .critical: return L10n.systemMonitorThermalCritical
        case nil: return L10n.systemMonitorUnavailable
        }
    }

    private var localIPValue: String {
        guard let addresses = engine.snapshot?.localIPAddresses,
              !addresses.isEmpty
        else { return L10n.systemMonitorUnavailable }
        return addresses.joined(separator: ", ")
    }

    private var publicIPValue: String {
        engine.snapshot?.publicIPAddress ?? L10n.systemMonitorUnavailable
    }

    private func summaryValue(average: Double?, peak: Double?) -> String {
        guard let average, let peak else { return L10n.systemMonitorUnavailable }
        return String(format: L10n.systemMonitorAveragePeak, average * 100, peak * 100)
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private func formatRate(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
    }
}
