import AppKit
import Combine
import SwiftUI

@MainActor
final class SystemMonitorService: NSObject, ObservableObject {
    @Published private(set) var settings: SystemMonitorSettings = .default
    @Published private(set) var theme: AppTheme = .gingerCat

    let engine: SystemMonitorEngine

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverController: NSHostingController<SystemMonitorPopoverView>?

    override init() {
        engine = SystemMonitorEngine()
        super.init()
        engine.onSnapshot = { [weak self] snapshot in
            self?.updateStatusItem(for: snapshot)
        }
    }

    func apply(settings: SystemMonitorSettings, theme: AppTheme) {
        self.settings = settings.normalized
        self.theme = theme
        engine.update(configuration: self.settings.configuration)
        if popoverController != nil {
            popoverController?.rootView = SystemMonitorPopoverView(
                engine: engine,
                theme: theme,
                enabledModules: self.settings.enabledModules
            )
            updatePopoverSize()
        }

        if self.settings.enabled {
            startIfNeeded()
        } else {
            stop()
        }
        updateStatusItem()
    }

    func stop() {
        popover?.close()
        popover = nil
        popoverController = nil
        engine.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func showPanel() {
        guard settings.enabled else { return }
        startIfNeeded()
        guard let button = statusItem?.button else { return }
        setupPopoverIfNeeded()
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func refreshLocalization() {
        statusItem?.button?.toolTip = L10n.systemMonitorTitle
        if let popoverController {
            popoverController.rootView = SystemMonitorPopoverView(
                engine: engine,
                theme: theme,
                enabledModules: settings.enabledModules
            )
            updatePopoverSize()
        }
    }

    private func startIfNeeded() {
        if statusItem == nil {
            setupStatusItem()
        }
        if !engine.isRunning {
            engine.start()
        }
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: L10n.systemMonitorTitle
            )
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = L10n.systemMonitorTitle
        }
        statusItem = item
    }

    private func setupPopoverIfNeeded() {
        guard popover == nil else { return }
        let controller = NSHostingController(
            rootView: SystemMonitorPopoverView(
                engine: engine,
                theme: theme,
                enabledModules: settings.enabledModules
            )
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 350, height: 470)
        popover.contentViewController = controller
        self.popoverController = controller
        self.popover = popover
        updatePopoverSize()
    }

    private func updateStatusItem(for snapshot: SystemMetricsSnapshot? = nil) {
        guard let button = statusItem?.button else { return }
        let current = snapshot ?? engine.snapshot
        switch settings.statusStyle {
        case .icon:
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: L10n.systemMonitorTitle
            )
        case .cpu:
            button.image = nil
            button.title = current?.cpuUsage.map { String(format: "CPU %.0f%%", $0 * 100) } ?? "CPU —"
        case .memory:
            button.image = nil
            button.title = current?.memoryUsedFraction.map { String(format: "MEM %.0f%%", $0 * 100) } ?? "MEM —"
        case .cpuAndMemory:
            button.image = nil
            let cpu = current?.cpuUsage.map { String(format: "C %.0f%%", $0 * 100) } ?? "C —"
            let memory = current?.memoryUsedFraction.map { String(format: "M %.0f%%", $0 * 100) } ?? "M —"
            button.title = "\(cpu) \(memory)"
        }
    }

    private func updatePopoverSize() {
        guard let popover else { return }
        let moduleCount = max(1, settings.enabledModules.count)
        let metricRows = max(1, (moduleCount + 1) / 2)
        var height: CGFloat = 10 + 38 + 6 + CGFloat(metricRows * 62)
        height += CGFloat(max(0, metricRows - 1) * 6)
        if settings.enabledModules.contains(.network) {
            height += 6 + 48
        }
        if settings.enabledModules.contains(.cpu) || settings.enabledModules.contains(.memory) {
            height += 6 + 46
        }
        height += 10
        popover.contentSize = NSSize(width: 350, height: min(560, height))
    }

    @objc private func togglePanel() {
        if popover?.isShown == true {
            popover?.close()
        } else {
            showPanel()
        }
    }
}
