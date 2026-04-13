import AppKit
import Carbon
import SwiftUI

private enum MeowPalette {
    static let accent = Color(red: 0.22, green: 0.3, blue: 0.54)
    static let danger = Color(red: 0.86, green: 0.21, blue: 0.2)

    static func launcherGradient(for scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.12, green: 0.14, blue: 0.19),
                Color(red: 0.08, green: 0.1, blue: 0.14),
            ]
        }

        return [
            Color(red: 0.96, green: 0.97, blue: 0.99),
            Color(red: 0.92, green: 0.94, blue: 0.97),
        ]
    }

    static func preferencesGradient(for scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.13, green: 0.15, blue: 0.2),
                Color(red: 0.09, green: 0.11, blue: 0.16),
            ]
        }

        return [
            Color(red: 0.97, green: 0.98, blue: 0.99),
            Color(red: 0.93, green: 0.95, blue: 0.98),
        ]
    }

    static func cardBackground(for scheme: ColorScheme, emphasized: Bool = false) -> Color {
        if scheme == .dark {
            return emphasized ? Color.white.opacity(0.16) : Color.white.opacity(0.1)
        }

        return emphasized ? Color.white.opacity(0.9) : Color.white.opacity(0.72)
    }

    static func stroke(for scheme: ColorScheme, emphasized: Bool = false) -> Color {
        if scheme == .dark {
            return emphasized ? Color.white.opacity(0.24) : Color.white.opacity(0.14)
        }

        return emphasized ? Color.white : Color.white.opacity(0.8)
    }

    static func iconChipBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.9)
    }

    static func capsuleBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.75)
    }
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    var onDismiss: () -> Void
    @State private var selectedID: SearchItem.ID?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: MeowPalette.launcherGradient(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MeowPalette.accent)

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
                        .background(MeowPalette.capsuleBackground(for: colorScheme), in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(MeowPalette.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MeowPalette.stroke(for: colorScheme), lineWidth: 1)
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.results) { item in
                                Button {
                                    selectedID = item.id
                                    viewModel.activate(item)
                                } label: {
                                    HStack(spacing: 12) {
                                        SearchItemIcon(item: item)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.primaryText)
                                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            Text(item.secondaryText)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        MeowPalette.cardBackground(for: colorScheme, emphasized: selectedID == item.id),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(MeowPalette.stroke(for: colorScheme, emphasized: selectedID == item.id), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
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
                }
            }
            .padding(14)
        }
        .frame(minWidth: 760, minHeight: 480)
        .id(lang.refreshToken)
        .onAppear {
            selectedID = viewModel.results.first?.id
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
                selectedID = newValue.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard notification.object is LauncherPanel else { return }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
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
        guard !viewModel.results.isEmpty else { return }
        if let selectedID,
           let selected = viewModel.results.first(where: { $0.id == selectedID }) {
            viewModel.activate(selected)
            return
        }
        let first = viewModel.results[0]
        selectedID = first.id
        viewModel.activate(first)
    }

    private func moveSelection(step: Int) {
        guard !viewModel.results.isEmpty else { return }

        guard let currentID = selectedID,
              let currentIndex = viewModel.results.firstIndex(where: { $0.id == currentID }) else {
            selectedID = viewModel.results[0].id
            return
        }

        let count = viewModel.results.count
        let nextIndex = (currentIndex + step + count) % count
        selectedID = viewModel.results[nextIndex].id
    }
}

private struct SearchItemIcon: View {
    let item: SearchItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch item {
            case .app(let app):
                let nsImage = NSWorkspace.shared.icon(forFile: app.url.path)
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(2)
            case .command:
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MeowPalette.accent)
            }
        }
        .frame(width: 32, height: 32)
        .background(MeowPalette.iconChipBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: MeowPalette.preferencesGradient(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MeowPalette.accent)
                        .frame(width: 36, height: 36)
                        .background(MeowPalette.iconChipBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            keyCode: viewModel.settings.hotkeyKeyCode,
                            modifiers: viewModel.settings.hotkeyModifiers
                        ) { keyCode, modifiers in
                            viewModel.settings.hotkeyKeyCode = keyCode
                            viewModel.settings.hotkeyModifiers = modifiers
                        }
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                        PreferenceLanguageRow(
                            language: Binding(
                                get: { viewModel.settings.language },
                                set: { viewModel.settings.language = $0 }
                            )
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                    }

                    if selectedSection == .appearance {
                        PreferenceToggleRow(
                            title: L10n.prefsDockTitle,
                            subtitle: L10n.prefsDockSubtitle,
                            symbol: "dock.rectangle",
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
                .background(MeowPalette.cardBackground(for: colorScheme, emphasized: true), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MeowPalette.stroke(for: colorScheme, emphasized: true), lineWidth: 1)
                )
                .animation(.snappy(duration: 0.28), value: selectedSection)

                HStack {
                    Spacer()
                    Button(L10n.quitMeow) {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MeowPalette.danger)
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
    let keyCode: UInt32
    let modifiers: UInt32
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MeowPalette.accent)
                .frame(width: 30, height: 30)
                .background(MeowPalette.iconChipBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
            .tint(isRecording ? .orange : MeowPalette.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MeowPalette.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MeowPalette.stroke(for: colorScheme), lineWidth: 1)
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
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MeowPalette.accent)
                .frame(width: 30, height: 30)
                .background(MeowPalette.iconChipBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
        .background(MeowPalette.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MeowPalette.stroke(for: colorScheme), lineWidth: 1)
        )
    }
}

private struct PreferenceLanguageRow: View {
    @Binding var language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MeowPalette.accent)
                .frame(width: 30, height: 30)
                .background(MeowPalette.iconChipBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
        .background(MeowPalette.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MeowPalette.stroke(for: colorScheme), lineWidth: 1)
        )
    }
}
