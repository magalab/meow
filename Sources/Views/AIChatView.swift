import AppKit
import SwiftUI

struct AIChatPanelView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let initialPrompt: String?
    @ObservedObject var historyStore: AIChatHistoryStore
    let onOpenPreferences: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSeedInitialPrompt = false
    @State private var keyMonitor: Any?

    private let service = AIChatService()

    private var settings: AISettings {
        viewModel.settings.ai
    }

    private var theme: AppTheme {
        viewModel.settings.theme
    }

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var messages: [AIChatMessage] {
        historyStore.messages(for: historyStore.selectedConversationID)
    }

    var body: some View {
        HStack(spacing: 0) {
            if settings.isConfigured, settings.chatHistoryEnabled {
                historySidebar
                Divider()
            }

            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                composer
            }
        }
        .frame(
            minWidth: settings.isConfigured && settings.chatHistoryEnabled ? 700 : 520,
            idealWidth: settings.isConfigured && settings.chatHistoryEnabled ? 780 : 580,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 620,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            installKeyMonitorIfNeeded()
            seedInitialPromptIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.aiChatHistoryTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    startNewConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L10n.aiChatNewConversation)
                .disabled(isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    if historyStore.conversations.isEmpty {
                        Text(L10n.aiChatHistoryEmpty)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }

                    ForEach(historyStore.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 188)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025))
    }

    private func conversationRow(_ conversation: AIChatConversation) -> some View {
        let isSelected = conversation.id == historyStore.selectedConversationID

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title.isEmpty ? L10n.aiChatUntitledConversation : conversation.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(conversationDateText(conversation.updatedAt))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                historyStore.deleteConversation(conversation.id)
                errorMessage = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.aiChatDeleteConversation)
            .disabled(isSending)
        }
        .padding(9)
        .background(
            isSelected ? palette.selectionBackground : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? palette.selectionStroke : Color.primary.opacity(0.055), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            guard !isSending else { return }
            historyStore.selectConversation(conversation.id)
            errorMessage = nil
        }
        .disabled(isSending)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.aiChatTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(settings.model.isEmpty ? L10n.aiChatNoModel : settings.model)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if !settings.isConfigured {
            notConfiguredView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if isSending {
                            sendingBubble
                                .id("sending")
                        }

                        if let errorMessage {
                            errorBubble(errorMessage)
                                .id("error")
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isSending) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: errorMessage) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(L10n.aiChatNotConfiguredTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(L10n.aiChatNotConfiguredSubtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(L10n.aiChatOpenSettings) {
                onOpenPreferences()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.preferencesAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    @ViewBuilder
    private func messageBubble(_ message: AIChatMessage) -> some View {
        let isUser = message.role == .user

        if isUser {
            HStack(alignment: .top) {
                Spacer(minLength: 50)

                ViewThatFits(in: .horizontal) {
                    userMessageBubble(message.content)
                        .fixedSize(horizontal: true, vertical: false)

                    userMessageBubble(message.content)
                        .frame(width: 420, alignment: .leading)
                }
            }
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(L10n.aiChatAssistant)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)
                        Button {
                            copy(message.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L10n.aiChatCopy)
                    }

                    AIAssistantMessageContentView(content: message.content, palette: palette)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                )

                Spacer(minLength: 50)
            }
        }
    }

    private func userMessageBubble(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.aiChatYou)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(content)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(palette.selectionBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.selectionStroke, lineWidth: 1)
        )
    }

    private var sendingBubble: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.72)
            Text(L10n.aiChatThinking)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBubble(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                AIComposerTextView(
                    text: $inputText,
                    placeholder: L10n.aiChatInputPlaceholder,
                    isEditable: settings.isConfigured && !isSending
                )
                .frame(height: 68)
            }
            .padding(6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Text(L10n.aiChatPrivacyHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    sendInput()
                } label: {
                    Label(L10n.aiChatSend, systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(palette.preferencesAccent)
                .disabled(!canSend)
            }
        }
        .padding(12)
    }

    private func seedInitialPromptIfNeeded() {
        guard !didSeedInitialPrompt else { return }
        didSeedInitialPrompt = true

        guard let initialPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !initialPrompt.isEmpty,
              settings.isConfigured
        else { return }

        historyStore.createConversation()
        inputText = initialPrompt
        sendInput()
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.keyWindow?.identifier == MeowWindowIdentifiers.aiChat else { return event }
            guard event.keyCode == 36 || event.keyCode == 76 else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) {
                return event
            }

            if canSend {
                sendInput()
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private var canSend: Bool {
        settings.isConfigured &&
            !isSending &&
            !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, settings.isConfigured, !isSending else { return }

        inputText = ""
        errorMessage = nil
        let conversationID = historyStore.ensureSelectedConversation()
        historyStore.append(AIChatMessage(role: .user, content: trimmed), to: conversationID)
        let outgoingMessages = historyStore.messages(for: conversationID)
        isSending = true

        Task {
            do {
                let response = try await service.send(messages: outgoingMessages, settings: settings)
                await MainActor.run {
                    historyStore.append(AIChatMessage(role: .assistant, content: response), to: conversationID)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func startNewConversation() {
        historyStore.createConversation()
        inputText = ""
        errorMessage = nil
    }

    private func conversationDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: LanguageManager.shared.currentLanguageCode.hasPrefix("zh") ? "zh-Hans" : "en")
        if calendar.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.18)) {
                if errorMessage != nil {
                    proxy.scrollTo("error", anchor: .bottom)
                } else if isSending {
                    proxy.scrollTo("sending", anchor: .bottom)
                } else if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct AIComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> ComposerTextContainerView {
        let view = ComposerTextContainerView()
        view.textView.delegate = context.coordinator
        view.textView.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        view.placeholderTextView.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return view
    }

    func updateNSView(_ nsView: ComposerTextContainerView, context: Context) {
        if nsView.textView.string != text {
            nsView.textView.string = text
        }
        nsView.placeholderTextView.string = placeholder
        nsView.placeholderTextView.isHidden = !text.isEmpty
        nsView.textView.isEditable = isEditable
        nsView.textView.textColor = isEditable ? .labelColor : .secondaryLabelColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class ComposerTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let placeholderTextView = PassthroughTextView()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width), height: max(0, bounds.height))
        textView.textContainer?.containerSize = NSSize(width: max(0, bounds.width), height: .greatestFiniteMagnitude)
        placeholderTextView.frame = textView.frame
        placeholderTextView.textContainer?.containerSize = textView.textContainer?.containerSize ?? .zero
    }

    private func setup() {
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)

        placeholderTextView.drawsBackground = false
        placeholderTextView.isEditable = false
        placeholderTextView.isSelectable = false
        placeholderTextView.textColor = .secondaryLabelColor
        placeholderTextView.alphaValue = 0.72
        placeholderTextView.textContainerInset = .zero
        placeholderTextView.textContainer?.lineFragmentPadding = 0
        placeholderTextView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(placeholderTextView)
    }
}

private final class PassthroughTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct AIAssistantMessageContentView: View {
    let content: String
    let palette: ThemePalette
    @State private var showsThinking = false

    private var parsed: AIParsedAssistantMessage {
        AIParsedAssistantMessage.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !parsed.thinking.isEmpty {
                DisclosureGroup(isExpanded: $showsThinking) {
                    Text(parsed.thinking)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.aiChatThinkingSection)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            if !parsed.answer.isEmpty {
                Text(parsed.answer)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AIParsedAssistantMessage {
    let thinking: String
    let answer: String

    static func parse(_ content: String) -> AIParsedAssistantMessage {
        let pattern = #"(?is)<think>(.*?)</think>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AIParsedAssistantMessage(thinking: "", answer: content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, range: fullRange)
        guard !matches.isEmpty else {
            return AIParsedAssistantMessage(thinking: "", answer: content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let thinking = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsContent.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let answer = regex
            .stringByReplacingMatches(in: content, range: fullRange, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AIParsedAssistantMessage(thinking: thinking, answer: answer)
    }
}
