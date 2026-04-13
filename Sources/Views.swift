import AppKit
import Carbon
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

    private var groupedResults: [(title: String, items: [SearchItem])] {
        let commands = viewModel.results.filter {
            if case .command = $0 { return true }
            return false
        }
        let apps = viewModel.results.filter {
            if case .app = $0 { return true }
            return false
        }

        var sections: [(title: String, items: [SearchItem])] = []
        if !commands.isEmpty {
            sections.append((L10n.launcherSectionCommands, commands))
        }
        if !apps.isEmpty {
            sections.append((L10n.launcherSectionApplications, apps))
        }
        return sections
    }

    private var orderedResults: [SearchItem] {
        groupedResults.flatMap(\ .items)
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
                                                (selectedID == item.id
                                                    ? palette.selectionBackground
                                                    : palette.surfaceBackground),
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

                switch event.keyCode {
                case 125: // Down arrow
                    moveSelection(step: 1)
                    return nil
                case 126: // Up arrow
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
    }

    private func activateCurrentSelection() {
        guard !orderedResults.isEmpty else { return }
        if let selectedID,
           let selected = orderedResults.first(where: { $0.id == selectedID }) {
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
              let currentIndex = orderedResults.firstIndex(where: { $0.id == currentID }) else {
            selectedID = orderedResults[0].id
            return
        }

        let count = orderedResults.count
        let nextIndex = (currentIndex + step + count) % count
        selectedID = orderedResults[nextIndex].id
    }
}

private struct SearchItemIcon: View {
    let item: SearchItem
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        Group {
            switch item {
            case .app(let app):
                LazyAppIconView(path: app.url.path)
            case .command:
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.launcherAccent)
            }
        }
        .frame(width: 32, height: 32)
        .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct LazyAppIconView: View {
    let path: String
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .onAppear {
            guard nsImage == nil else { return }
            nsImage = NSWorkspace.shared.icon(forFile: path)
        }
        .onDisappear {
            nsImage = nil
        }
    }
}

struct PreferencesView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general
        case appearance

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .general: return L10n.prefsSectionGeneral
            case .appearance: return L10n.prefsSectionAppearance
            }
        }
    }

    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: Section = .general

    private var palette: ThemePalette {
        MeowTheme.palette(theme: viewModel.settings.theme, scheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.preferencesGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.preferencesAccent)
                        .frame(width: 36, height: 36)
                        .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.prefsTitle)
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text(L10n.prefsSubtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("", selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.localizedTitle).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 10) {
                    if selectedSection == .general {
                        PreferenceToggleRow(
                            title: L10n.prefsAutoLaunchTitle,
                            subtitle: L10n.prefsAutoLaunchSubtitle,
                            symbol: "power.circle",
                            theme: viewModel.settings.theme,
                            isOn: animatedBinding(
                                get: { viewModel.settings.autoLaunch },
                                set: { viewModel.settings.autoLaunch = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                        PreferenceHotkeyRecorderRow(
                            title: L10n.prefsHotkeyTitle,
                            subtitle: L10n.prefsHotkeySubtitle,
                            symbol: "keyboard",
                            theme: viewModel.settings.theme,
                            keyCode: viewModel.settings.hotkeyKeyCode,
                            modifiers: viewModel.settings.hotkeyModifiers
                        ) { keyCode, modifiers in
                            viewModel.settings.hotkeyKeyCode = keyCode
                            viewModel.settings.hotkeyModifiers = modifiers
                        }
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                        PreferenceLanguageRow(
                            theme: viewModel.settings.theme,
                            language: Binding(
                                get: { viewModel.settings.language },
                                set: { viewModel.settings.language = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                    }

                    if selectedSection == .appearance {
                        PreferenceThemeRow(
                            theme: Binding(
                                get: { viewModel.settings.theme },
                                set: { viewModel.settings.theme = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                        PreferenceToggleRow(
                            title: L10n.prefsDockTitle,
                            subtitle: L10n.prefsDockSubtitle,
                            symbol: "dock.rectangle",
                            theme: viewModel.settings.theme,
                            isOn: animatedBinding(
                                get: { viewModel.settings.showDockIcon },
                                set: { viewModel.settings.showDockIcon = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                        PreferenceToggleRow(
                            title: L10n.prefsMenuBarTitle,
                            subtitle: L10n.prefsMenuBarSubtitle,
                            symbol: "menubar.rectangle",
                            theme: viewModel.settings.theme,
                            isOn: animatedBinding(
                                get: { viewModel.settings.showStatusItem },
                                set: { viewModel.settings.showStatusItem = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(minHeight: 196, alignment: .top)
                .padding(12)
                .background(palette.preferencesPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.preferencesPanelStroke, lineWidth: 1)
                )
                .animation(.snappy(duration: 0.28), value: selectedSection)

                HStack {
                    Spacer()
                    Button(L10n.quitMeow) {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.danger)
                    .controlSize(.large)
                }
            }
            .padding(22)
        }
        .frame(width: 560)
        .id(lang.refreshToken)
    }

    private func animatedBinding(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(
            get: get,
            set: { newValue in
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.08)) {
                    set(newValue)
                }
            }
        )
    }
}

private struct PreferenceHotkeyRecorderRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    let keyCode: UInt32
    let modifiers: UInt32
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(isRecording ? L10n.prefsHotkeyRecordingHint : subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isRecording ? L10n.prefsHotkeyRecording : hotkeyLabel(keyCode: keyCode, modifiers: modifiers)) {
                startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isRecording ? .orange : palette.preferencesAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)

            if keyCode == 53 {
                // Esc cancels recording.
                isRecording = false
                stopRecording()
                return nil
            }

            if isModifierOnlyKey(keyCode) {
                return nil
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            if modifiers == 0 {
                return nil
            }

            onSave(keyCode, modifiers)
            isRecording = false
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private func hotkeyLabel(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    private func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "Key \(keyCode)"
        }
    }

    private func isModifierOnlyKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

private struct PreferenceThemeRow: View {
    @Binding var theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsThemeTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsThemeSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(palette.launcherAccent)
                Circle()
                    .fill(palette.preferencesAccent)
            }
            .frame(width: 28, height: 12)

            Picker("", selection: $theme) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

private struct PreferenceLanguageRow: View {
    let theme: AppTheme
    @Binding var language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsLanguageTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsLanguageSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}
