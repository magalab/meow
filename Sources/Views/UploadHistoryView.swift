import SwiftUI

private enum UploadHistoryAlert: Identifiable {
    case delete(UploadHistoryEntry)
    case clear
    case error(String)

    var id: String {
        switch self {
        case let .delete(entry): return "delete-\(entry.id.uuidString)"
        case .clear: return "clear"
        case let .error(message): return "error-\(message)"
        }
    }
}

struct UploadHistoryView: View {
    @ObservedObject var store: UploadHistoryStore
    let sourceName: (UploadHistoryEntry) -> String?
    let onCopy: (UploadHistoryEntry) -> Void
    let onDelete: (UploadHistoryEntry, Bool) async throws -> Void
    let onClear: (Bool) async throws -> Void
    @State private var deleteRemoteObjects = false
    @State private var alert: UploadHistoryAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.uploadHistoryTitle).font(.headline)
                Spacer()
                if !store.entries.isEmpty {
                    Button(L10n.uploadHistoryClear) { alert = .clear }
                        .buttonStyle(.borderless)
                }
            }
            if !store.entries.isEmpty {
                Toggle(L10n.uploadHistoryDeleteRemote, isOn: $deleteRemoteObjects)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(deleteRemoteObjects ? Color.red : Color.secondary)
            }
            if store.entries.isEmpty {
                Text(L10n.uploadHistoryEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.entries) { entry in
                    HStack(spacing: 10) {
                        if let url = store.thumbnailURL(for: entry), let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            Image(systemName: "doc").frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.filename).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.backendName ?? sourceName(entry) ?? L10n.uploadSourceS3)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.14), in: Capsule())
                            }
                        }
                        Spacer()
                        Button { onCopy(entry) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help(L10n.uploadHistoryCopy)
                        Button(role: .destructive) { alert = .delete(entry) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case let .delete(entry):
                Alert(
                    title: Text(L10n.uploadHistoryDeleteTitle),
                    message: Text(deleteMessage(clearAll: false)),
                    primaryButton: .destructive(Text(L10n.uploadHistoryDeleteAction)) {
                        Task { await delete(entry) }
                    },
                    secondaryButton: .cancel()
                )
            case .clear:
                Alert(
                    title: Text(L10n.uploadHistoryDeleteTitle),
                    message: Text(deleteMessage(clearAll: true)),
                    primaryButton: .destructive(Text(L10n.uploadHistoryDeleteAction)) {
                        Task { await clear() }
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                Alert(title: Text(L10n.uploadErrorTitle), message: Text(message), dismissButton: .default(Text(L10n.actionOK)))
            }
        }
    }

    private func deleteMessage(clearAll: Bool) -> String {
        let base = clearAll ? L10n.uploadHistoryDeleteAllMessage : L10n.uploadHistoryDeleteSingleMessage
        return deleteRemoteObjects ? base + L10n.uploadHistoryDeleteRemoteWarning : base
    }

    private func delete(_ entry: UploadHistoryEntry) async {
        do {
            try await onDelete(entry, deleteRemoteObjects)
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func clear() async {
        do {
            try await onClear(deleteRemoteObjects)
        } catch {
            alert = .error(error.localizedDescription)
        }
    }
}
