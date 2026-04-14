import AppKit
import SwiftUI

extension Notification.Name {
    static let meowLauncherDidHide = Notification.Name("meow.launcher.didHide")
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    var onDismiss: () -> Void
    @State private var selectedID: SearchItem.ID?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var keyMonitor: Any?
    @State private var scrollResetToken: Int = 0
    @State private var showActionMenu = false
    @State private var actionMenuSelectionIndex = 0

    private var groupedResults: [(title: String, items: [SearchItem])] {
        let commands = viewModel.results.filter {
            if case .command = $0 { return true }
            return false
        }
        let apps = viewModel.results.filter {
            if case .app = $0 { return true }
            return false
        }
        let clipboard = viewModel.results.filter {
            if case .clipboard = $0 { return true }
            return false
        }

        var sections: [(title: String, items: [SearchItem])] = []
        if !commands.isEmpty {
            sections.append((L10n.launcherSectionCommands, commands))
        }
        if !apps.isEmpty {
            sections.append((L10n.launcherSectionApplications, apps))
        }
        if !clipboard.isEmpty {
            sections.append((L10n.launcherSectionClipboard, clipboard))
        }
        return sections
    }

    private var orderedResults: [SearchItem] {
        groupedResults.flatMap(\.items)
    }

    private var palette: ThemePalette {
        MeowTheme.palette(theme: viewModel.settings.theme, scheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.launcherGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.launcherAccent)

                    TextField(L10n.searchPlaceholder, text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            activateCurrentSelection()
                        }

                    Spacer()

                    Text(L10n.filterAll)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(palette.filterCapsuleBackground, in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(groupedResults.enumerated()), id: \.offset) { sectionIndex, section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .padding(.horizontal, 8)
                                        .padding(.top, sectionIndex == 0 ? 0 : 6)

                                    ForEach(section.items) { item in
                                        Button {
                                            selectedID = item.id
                                            viewModel.activate(item)
                                        } label: {
                                            HStack(spacing: 12) {
                                                SearchItemIcon(item: item, theme: viewModel.settings.theme)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    let isSelected = selectedID == item.id
                                                    Text(item.primaryText)
                                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(Color.primary)
                                                        .lineLimit(1)

                                                    Text(item.secondaryText)
                                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                                        .foregroundStyle(isSelected ? Color.primary.opacity(0.82) : Color.secondary)
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(
                                                selectedID == item.id
                                                    ? palette.selectionBackground
                                                    : palette.surfaceBackground,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(
                                                        selectedID == item.id
                                                            ? palette.selectionStroke
                                                            : palette.surfaceStroke,
                                                        lineWidth: 1
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .id(item.id)
                                        .modifier(ClipboardContextMenu(item: item, onDelete: { viewModel.deleteClipboardItem(item) }))
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.snappy(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onChange(of: scrollResetToken) { _, _ in
                        guard let firstID = orderedResults.first?.id else { return }
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(minWidth: 760, minHeight: 480)
        .id(lang.refreshToken)
        .onAppear {
            selectedID = orderedResults.first?.id
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                guard NSApp.keyWindow is LauncherPanel else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let selectedItem = selectedSearchItem()

                switch event.keyCode {
                case 53: // Escape
                    if showActionMenu {
                        showActionMenu = false
                    } else if !viewModel.query.isEmpty {
                        viewModel.query = ""
                    } else {
                        onDismiss()
                    }
                    return nil
                case 40: // K
                    if flags.contains(.command) {
                        toggleActionMenu()
                        return nil
                    }
                    return event
                case 36: // Return/Enter
                    if showActionMenu {
                        if flags.contains(.command), canPerformAction(.showInFinder, on: selectedItem) {
                            if let selectedItem {
                                executeActionMenu(.showInFinder, selected: selectedItem)
                            }
                            return nil
                        }
                        executeHighlightedAction(selectedItem)
                        return nil
                    }
                    if flags.contains(.command) {
                        revealSelectedInFinder()
                        return nil
                    }
                    return event
                case 8: // C
                    if showActionMenu, flags.contains(.command) {
                        if flags.contains(.shift) {
                            if canPerformAction(.copyPath, on: selectedItem), let selectedItem {
                                executeActionMenu(.copyPath, selected: selectedItem)
                            }
                        } else {
                            if canPerformAction(.copy, on: selectedItem), let selectedItem {
                                executeActionMenu(.copy, selected: selectedItem)
                            }
                        }
                        return nil
                    }
                    return event
                case 51: // Delete / Backspace
                    if showActionMenu, flags.contains(.command) {
                        if canPerformAction(.delete, on: selectedItem), let selectedItem {
                            executeActionMenu(.delete, selected: selectedItem)
                        }
                        return nil
                    }
                    return event
                case 125: // Down arrow
                    if showActionMenu {
                        moveActionMenuSelection(step: 1, selectedItem)
                        return nil
                    }
                    moveSelection(step: 1)
                    return nil
                case 126: // Up arrow
                    if showActionMenu {
                        moveActionMenuSelection(step: -1, selectedItem)
                        return nil
                    }
                    moveSelection(step: -1)
                    return nil
                default:
                    return event
                }
            }
        }
        .onChange(of: viewModel.results) { _, newValue in
            if selectedID == nil || !newValue.contains(where: { $0.id == selectedID }) {
                selectedID = orderedResults.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard notification.object is LauncherPanel else { return }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meowLauncherDidHide)) { _ in
            DispatchQueue.main.async {
                selectedID = orderedResults.first?.id
                scrollResetToken += 1
            }
        }
        .onExitCommand {
            onDismiss()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .overlay {
            if showActionMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showActionMenu = false
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActionMenu, let selectedID, let selected = orderedResults.first(where: { $0.id == selectedID }) {
                let actions = actionMenuActions(for: selected)
                ActionMenu(
                    selectedItem: selected,
                    highlightedAction: actions.isEmpty ? nil : actions[actionMenuSelectionIndex.clamped(to: 0 ... (actions.count - 1))],
                    onAction: { action in
                        executeActionMenu(action, selected: selected)
                    }
                )
                .frame(width: 290)
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private func activateCurrentSelection() {
        guard !orderedResults.isEmpty else { return }
        if let selectedID,
           let selected = orderedResults.first(where: { $0.id == selectedID })
        {
            viewModel.activate(selected)
            return
        }
        let first = orderedResults[0]
        selectedID = first.id
        viewModel.activate(first)
    }

    private func moveSelection(step: Int) {
        guard !orderedResults.isEmpty else { return }

        guard let currentID = selectedID,
              let currentIndex = orderedResults.firstIndex(where: { $0.id == currentID })
        else {
            selectedID = orderedResults[0].id
            return
        }

        let count = orderedResults.count
        let nextIndex = (currentIndex + step + count) % count
        selectedID = orderedResults[nextIndex].id
    }

    private func revealSelectedInFinder() {
        guard let selectedID,
              let selected = orderedResults.first(where: { $0.id == selectedID }),
              case let .app(app) = selected else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    private func showActionMenuForSelected() {
        guard selectedID != nil else { return }
        actionMenuSelectionIndex = 0
        showActionMenu = true
    }

    private func toggleActionMenu() {
        if showActionMenu {
            showActionMenu = false
        } else {
            showActionMenuForSelected()
        }
    }

    private func copySelectedPath() {
        guard let selectedID,
              let selected = orderedResults.first(where: { $0.id == selectedID }),
              case let .app(app) = selected else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(app.url.path, forType: .string)
    }

    private func copyClipboardContent() {
        guard let selectedID,
              let selected = orderedResults.first(where: { $0.id == selectedID }) else { return }
        viewModel.copyClipboardItem(selected)
    }

    private func deleteSelectedClipboardItem() {
        guard let selectedID,
              let selected = orderedResults.first(where: { $0.id == selectedID }) else { return }
        viewModel.deleteClipboardItem(selected)
    }

    private func selectedSearchItem() -> SearchItem? {
        guard let selectedID else { return nil }
        return orderedResults.first(where: { $0.id == selectedID })
    }

    private func actionMenuActions(for item: SearchItem) -> [ActionMenuAction] {
        switch item {
        case .app:
            return [.open, .showInFinder, .copyPath]
        case .clipboard:
            return [.paste, .copy, .delete]
        case .command:
            return [.execute]
        }
    }

    private func moveActionMenuSelection(step: Int, _ selectedItem: SearchItem?) {
        guard let selectedItem else { return }
        let actions = actionMenuActions(for: selectedItem)
        guard !actions.isEmpty else { return }
        let count = actions.count
        actionMenuSelectionIndex = (actionMenuSelectionIndex + step + count) % count
    }

    private func executeHighlightedAction(_ selectedItem: SearchItem?) {
        guard let selectedItem else { return }
        let actions = actionMenuActions(for: selectedItem)
        guard !actions.isEmpty else { return }
        let index = actionMenuSelectionIndex.clamped(to: 0 ... (actions.count - 1))
        executeActionMenu(actions[index], selected: selectedItem)
    }

    private func canPerformAction(_ action: ActionMenuAction, on selectedItem: SearchItem?) -> Bool {
        guard let selectedItem else { return false }
        switch (selectedItem, action) {
        case (.app, .open), (.app, .showInFinder), (.app, .copyPath):
            return true
        case (.clipboard, .paste), (.clipboard, .copy), (.clipboard, .delete):
            return true
        case (.command, .execute):
            return true
        default:
            return false
        }
    }

    private func executeActionMenu(_ action: ActionMenuAction, selected: SearchItem) {
        switch action {
        case .open, .execute, .paste:
            viewModel.activate(selected)
        case .showInFinder:
            revealSelectedInFinder()
        case .copyPath:
            copySelectedPath()
        case .copy:
            copyClipboardContent()
        case .delete:
            viewModel.deleteClipboardItem(selected)
        }
        showActionMenu = false
    }
}
