import AppKit
import SwiftUI

struct RecordingHistoryView: View {
    @ObservedObject var store: RecordingStore
    let theme: AppTheme
    let onDelete: (RecordingArtifact) -> Void
    let onTrim: (RecordingArtifact) -> Void

    @State private var query = ""
    @State private var showClearConfirmation = false
    @State private var layoutMode = HistoryLayoutMode.list

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading) {
                    Text(L10n.recordingHistoryTitle).font(.headline)
                    Text(String(format: L10n.recordingHistoryCount, store.artifacts.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(L10n.recordingHistorySearch, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Picker("", selection: $layoutMode) {
                    ForEach(HistoryLayoutMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 128)
                .controlSize(.small)
                Button(L10n.recordingHistoryOpenFolder) {
                    let directory = store.artifacts.first?.fileURL.deletingLastPathComponent()
                        ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("Meow")
                    NSWorkspace.shared.open(directory)
                }
                Button(L10n.recordingHistoryClear) { showClearConfirmation = true }
                    .disabled(store.artifacts.isEmpty)
            }
            .padding(14)
            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    L10n.recordingHistoryEmptyTitle,
                    systemImage: "film",
                    description: Text(L10n.recordingHistoryEmptySubtitle)
                )
            } else {
                switch layoutMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered) { artifact in
                                artifactCard(artifact)
                            }
                        }
                        .padding(16)
                    }
                case .list:
                    List(filtered) { artifact in
                        artifactListRow(artifact)
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .alert(L10n.recordingHistoryClearTitle, isPresented: $showClearConfirmation) {
            Button(L10n.actionCancel, role: .cancel) {}
            Button(L10n.recordingHistoryClearConfirm, role: .destructive) {
                store.clear()
            }
        } message: {
            Text(L10n.recordingHistoryClearMessage)
        }
    }

    private func artifactCard(_ artifact: RecordingArtifact) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail(artifact)
                .frame(maxWidth: .infinity)
                .frame(height: 150)

            VStack(alignment: .leading, spacing: 4) {
                Text(artifact.fileURL.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(metadata(artifact))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                iconButton("play.fill", help: L10n.recordingPreviewOpen) {
                    NSWorkspace.shared.open(artifact.fileURL)
                }
                iconButton("folder", help: L10n.actionMenuShowInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact.fileURL])
                }
                iconButton("scissors", help: L10n.recordingPreviewTrim) {
                    onTrim(artifact)
                }
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

    private func artifactListRow(_ artifact: RecordingArtifact) -> some View {
        HStack(spacing: 12) {
            thumbnail(artifact)
                .frame(width: 128, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(metadata(artifact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            iconButton("play.fill", help: L10n.recordingPreviewOpen) {
                NSWorkspace.shared.open(artifact.fileURL)
            }
            iconButton("folder", help: L10n.actionMenuShowInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([artifact.fileURL])
            }
            iconButton("scissors", help: L10n.recordingPreviewTrim) {
                onTrim(artifact)
            }
            iconButton("trash", help: L10n.actionMenuDelete, role: .destructive) {
                onDelete(artifact)
            }
        }
        .padding(.vertical, 4)
    }

    private func thumbnail(_ artifact: RecordingArtifact) -> some View {
        Group {
            if let url = artifact.thumbnailURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .background(.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private var filtered: [RecordingArtifact] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.artifacts }
        return store.artifacts.filter {
            $0.fileURL.lastPathComponent.localizedCaseInsensitiveContains(query)
                || $0.source.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func metadata(_ artifact: RecordingArtifact) -> String {
        let duration = Duration.seconds(artifact.duration).formatted(.time(pattern: .minuteSecond))
        let size = ByteCountFormatter.string(fromByteCount: artifact.fileSize, countStyle: .file)
        let dimensions = artifact.width > 0 ? "\(artifact.width) × \(artifact.height) · " : ""
        return "\(dimensions)\(duration) · \(size) · \(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
