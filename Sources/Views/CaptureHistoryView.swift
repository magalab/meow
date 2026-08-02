import AppKit
import SwiftUI

enum HistoryLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .grid: return L10n.historyLayoutGrid
        case .list: return L10n.historyLayoutList
        }
    }
}

struct CaptureHistoryView: View {
    @ObservedObject var store: CaptureStore
    let theme: AppTheme
    let onCopy: (CaptureArtifact) -> Void
    let onPin: (CaptureArtifact) -> Void
    let onEdit: (CaptureArtifact) -> Void
    let onRecognizeText: (CaptureArtifact) -> Void
    let onTranslate: (CaptureArtifact) -> Void
    let onScanQRCode: (CaptureArtifact) -> Void
    let onAskAI: (CaptureArtifact) -> Void
    let onSendToWhiteboard: ((CaptureArtifact) -> Void)?
    let onDelete: (CaptureArtifact) -> Void
    let onClear: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showClearConfirmation = false
    @State private var query = ""
    @State private var layoutMode = HistoryLayoutMode.grid

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.artifacts.isEmpty {
                ContentUnavailableView(
                    L10n.screenshotHistoryEmptyTitle,
                    systemImage: "photo.stack",
                    description: Text(L10n.screenshotHistoryEmptySubtitle)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch layoutMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredArtifacts) { artifact in
                                artifactCard(artifact)
                            }
                        }
                        .padding(16)
                    }
                case .list:
                    List(filteredArtifacts) { artifact in
                        artifactListRow(artifact)
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(L10n.screenshotHistoryClearTitle, isPresented: $showClearConfirmation) {
            Button(L10n.actionCancel, role: .cancel) {}
            Button(L10n.screenshotHistoryClearConfirm, role: .destructive) {
                onClear()
            }
        } message: {
            Text(L10n.screenshotHistoryClearMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 32, height: 32)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.screenshotHistoryTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(String(format: L10n.screenshotHistoryCount, store.artifacts.count))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(L10n.screenshotHistorySearch, text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)

            Picker("", selection: $layoutMode) {
                ForEach(HistoryLayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 128)
            .controlSize(.small)

            Button(L10n.screenshotHistoryOpenFolder) {
                if let directory = store.artifacts.first?.imageURL.deletingLastPathComponent() {
                    NSWorkspace.shared.open(directory)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.artifacts.isEmpty)

            Button(L10n.screenshotHistoryClear) {
                showClearConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.artifacts.isEmpty)
        }
        .padding(14)
    }

    private func artifactCard(_ artifact: CaptureArtifact) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let image = NSImage(contentsOf: artifact.thumbnailURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 138)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kindName(artifact.kind))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("\(artifact.width) × \(artifact.height) · \(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 7) {
                iconButton("pencil.and.outline", help: L10n.actionMenuEditImage) {
                    onEdit(artifact)
                }
                iconButton("doc.on.doc", help: L10n.actionMenuCopy) {
                    onCopy(artifact)
                }
                iconButton("pin", help: L10n.actionMenuPinImage) {
                    onPin(artifact)
                }
                if let onSendToWhiteboard {
                    iconButton("scribble.variable", help: L10n.whiteboardSendImage) {
                        onSendToWhiteboard(artifact)
                    }
                }
                Menu {
                    Button(L10n.actionMenuRecognizeText) {
                        onRecognizeText(artifact)
                    }
                    Button(L10n.actionMenuTranslateImage) {
                        onTranslate(artifact)
                    }
                    Button(L10n.actionMenuScanQRCode) {
                        onScanQRCode(artifact)
                    }
                    Button(L10n.actionMenuAskAI) {
                        onAskAI(artifact)
                    }
                    Divider()
                    Button(L10n.actionMenuShowInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([artifact.imageURL])
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.actionMenuMore)
                Spacer()
                iconButton("trash", help: L10n.actionMenuDelete, role: .destructive) {
                    onDelete(artifact)
                }
            }
        }
        .padding(10)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func artifactListRow(_ artifact: CaptureArtifact) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = NSImage(contentsOf: artifact.thumbnailURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, height: 72)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(kindName(artifact.kind))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("\(artifact.width) × \(artifact.height) · \(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let ocrText = artifact.ocrText, !ocrText.isEmpty {
                    Text(ocrText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            iconButton("pencil.and.outline", help: L10n.actionMenuEditImage) {
                onEdit(artifact)
            }
            iconButton("doc.on.doc", help: L10n.actionMenuCopy) {
                onCopy(artifact)
            }
            iconButton("pin", help: L10n.actionMenuPinImage) {
                onPin(artifact)
            }
            if let onSendToWhiteboard {
                iconButton("scribble.variable", help: L10n.whiteboardSendImage) {
                    onSendToWhiteboard(artifact)
                }
            }
            Menu {
                Button(L10n.actionMenuRecognizeText) {
                    onRecognizeText(artifact)
                }
                Button(L10n.actionMenuTranslateImage) {
                    onTranslate(artifact)
                }
                Button(L10n.actionMenuScanQRCode) {
                    onScanQRCode(artifact)
                }
                Button(L10n.actionMenuAskAI) {
                    onAskAI(artifact)
                }
                Divider()
                Button(L10n.actionMenuShowInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact.imageURL])
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.actionMenuMore)

            iconButton("trash", help: L10n.actionMenuDelete, role: .destructive) {
                onDelete(artifact)
            }
        }
        .padding(.vertical, 4)
    }

    private var filteredArtifacts: [CaptureArtifact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.artifacts }
        return store.artifacts.filter { artifact in
            let haystack = [
                artifact.ocrText ?? "",
                kindName(artifact.kind),
                "\(artifact.width)x\(artifact.height)",
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private func kindName(_ kind: CaptureArtifactKind) -> String {
        switch kind {
        case .region: return L10n.screenshotKindRegion
        case .window: return L10n.screenshotKindWindow
        case .display: return L10n.screenshotKindDisplay
        case .edited: return L10n.screenshotKindEdited
        }
    }
}
