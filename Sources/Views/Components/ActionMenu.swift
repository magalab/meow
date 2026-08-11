import SwiftUI

enum ActionMenuAction: String, Hashable {
    case open
    case openImage
    case saveImageAs
    case showInFinder
    case copyPath
    case paste
    case copy
    case pinHistory
    case unpinHistory
    case speak
    case askAI
    case pin
    case recognizeText
    case translateImageText
    case scanQRCode
    case edit
    case sendToWhiteboard
    case delete
    case execute
}

struct ActionMenu: View {
    let selectedItem: SearchItem
    let showsSpeakAction: Bool
    let showsWhiteboardAction: Bool
    let highlightedAction: ActionMenuAction?
    let onAction: (ActionMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch selectedItem {
            case .app:
                menuRow(action: .open, title: L10n.actionMenuOpen, systemImage: "app.fill", shortcuts: ["↩"])
                menuRow(action: .showInFinder, title: L10n.actionMenuShowInFinder, systemImage: "folder", shortcuts: ["⌘", "↩"])
                menuRow(action: .copyPath, title: L10n.actionMenuCopyPath, systemImage: "doc.on.clipboard", shortcuts: ["⌘", "⇧", "C"])

            case let .clipboard(entry):
                menuRow(action: .paste, title: L10n.actionMenuPaste, systemImage: "doc.on.clipboard", shortcuts: ["↩"])
                menuRow(action: .copy, title: L10n.actionMenuCopy, systemImage: "doc.on.clipboard.fill", shortcuts: ["⌘", "C"])
                menuRow(
                    action: entry.isPinned ? .unpinHistory : .pinHistory,
                    title: entry.isPinned ? L10n.clipboardUnpin : L10n.clipboardPin,
                    systemImage: entry.isPinned ? "pin.slash" : "pin",
                    shortcuts: ["⌘", "P"]
                )
                if case .image = entry.content {
                    if showsWhiteboardAction {
                        menuRow(
                            action: .sendToWhiteboard,
                            title: L10n.whiteboardSendImage,
                            systemImage: "scribble.variable",
                            shortcuts: []
                        )
                    }
                    menuRow(action: .openImage, title: L10n.actionMenuOpen, systemImage: "arrow.up.right.square", shortcuts: [])
                    menuRow(action: .saveImageAs, title: L10n.actionMenuSaveAs, systemImage: "square.and.arrow.down", shortcuts: [])
                    menuRow(action: .edit, title: L10n.actionMenuEditImage, systemImage: "pencil.and.outline", shortcuts: [])
                    menuRow(action: .pin, title: L10n.actionMenuPinImage, systemImage: "pin", shortcuts: [])
                    menuRow(action: .recognizeText, title: L10n.actionMenuRecognizeText, systemImage: "text.viewfinder", shortcuts: [])
                    menuRow(action: .translateImageText, title: L10n.actionMenuTranslateImage, systemImage: "translate", shortcuts: [])
                    menuRow(action: .scanQRCode, title: L10n.actionMenuScanQRCode, systemImage: "qrcode.viewfinder", shortcuts: [])
                }
                if showsSpeakAction, case .text = entry.content {
                    menuRow(action: .speak, title: L10n.actionMenuSpeak, systemImage: "speaker.wave.2", shortcuts: [])
                }
                menuRow(action: .askAI, title: L10n.actionMenuAskAI, systemImage: "sparkles", shortcuts: ["⌘", "A"])
                menuRow(action: .delete, title: L10n.actionMenuDelete, systemImage: "trash", shortcuts: ["⌘", "⌫"], isDanger: true)

            case .command:
                menuRow(action: .execute, title: L10n.actionMenuExecute, systemImage: "terminal", shortcuts: ["↩"])
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private func menuRow(
        action: ActionMenuAction,
        title: String,
        systemImage: String,
        shortcuts: [String],
        isDanger: Bool = false
    ) -> some View {
        let isHighlighted = highlightedAction == action

        return Button(action: { onAction(action) }) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer(minLength: 8)

                ShortcutKeycaps(keys: shortcuts)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHighlighted ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDanger ? Color.red : Color.primary)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct ShortcutKeycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}
