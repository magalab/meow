import AppKit
import SwiftUI

private enum FileHostingPreferencePage: String, CaseIterable, Identifiable {
    case configuration
    case upload
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configuration: return L10n.uploadPageConfiguration
        case .upload: return L10n.uploadPageUpload
        case .history: return L10n.uploadPageHistory
        }
    }
}

private enum S3Preset: String, CaseIterable, Identifiable {
    case aws, r2, minio, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aws: return "AWS S3"
        case .r2: return "Cloudflare R2"
        case .minio: return "MinIO"
        case .custom: return L10n.uploadPresetCustom
        }
    }
}

struct FileHostingPreferencesView: View {
    @Binding var settings: FileHostSettings
    @ObservedObject var service: FileUploadService
    let theme: AppTheme
    @State private var secret = ""
    @State private var message = ""
    @State private var preset = S3Preset.custom
    @State private var selectedPage = FileHostingPreferencePage.configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker(L10n.uploadConfiguration, selection: $settings.selectedS3ConfigID) {
                    ForEach(settings.s3Configurations, id: \.id) { config in
                        Text(config.name).tag(config.id)
                    }
                }
                .onChange(of: settings.selectedS3ConfigID) { _, _ in loadSelectedConfiguration() }
                Button {
                    addConfiguration()
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.uploadAddConfiguration)
                Button(role: .destructive) {
                    deleteSelectedConfiguration()
                } label: {
                    Image(systemName: "minus")
                }
                .help(L10n.uploadDeleteConfiguration)
                .disabled(settings.s3Configurations.count <= 1)
            }

            Toggle(L10n.uploadEnabled, isOn: $settings.s3.isEnabled)
                .font(.headline)

            Picker("", selection: $selectedPage) {
                ForEach(FileHostingPreferencePage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)

            switch selectedPage {
            case .configuration:
                configurationPage
            case .upload:
                uploadPage
            case .history:
                historyPage
            }
        }
        .padding(14)
        .animation(.snappy(duration: 0.22), value: selectedPage)
        .onAppear {
            loadSelectedConfiguration()
        }
    }

    private var configurationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(L10n.uploadS3Configuration) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    field(L10n.uploadConfigurationName, text: $settings.s3.name)
                    GridRow {
                        Text(L10n.uploadPreset)
                        Picker("", selection: Binding(
                            get: { preset },
                            set: { value in
                                preset = value
                                applyPreset(value)
                            }
                        )) {
                            ForEach(S3Preset.allCases) { preset in Text(preset.title).tag(preset) }
                        }
                        .labelsHidden()
                    }
                    endpointField
                    regionField
                    field(L10n.uploadBucket, text: $settings.s3.bucket)
                    field(L10n.uploadAccessKeyID, text: $settings.s3.accessKeyID)
                    GridRow {
                        Text(L10n.uploadSecretAccessKey)
                        SecureField("", text: $secret)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveSecret() }
                    }
                    field(L10n.uploadObjectKeyTemplate, text: $settings.s3.objectKeyTemplate)
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Text(L10n.uploadObjectKeyHint).font(.caption).foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text(L10n.uploadURLStrategy)
                        Picker("", selection: $settings.s3.publicURLStrategy) {
                            Text(L10n.uploadURLCustom).tag(S3PublicURLStrategy.customDomain)
                            Text(L10n.uploadURLPublic).tag(S3PublicURLStrategy.publicBucket)
                            Text(L10n.uploadURLPresigned).tag(S3PublicURLStrategy.presigned)
                        }.labelsHidden()
                    }
                    if settings.s3.publicURLStrategy == .presigned {
                        GridRow {
                            Text(L10n.uploadExpiration)
                            TextField("", value: $settings.s3.presignedURLExpiration, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        field(L10n.uploadPublicBaseURL, text: $settings.s3.publicBaseURL)
                    }
                    GridRow {
                        Text(L10n.uploadURLStyle)
                        Picker("", selection: $settings.s3.urlStyle) {
                            Text(L10n.uploadURLStylePath).tag(S3URLStyle.path)
                            Text(L10n.uploadURLStyleVirtualHosted).tag(S3URLStyle.virtualHosted)
                        }.labelsHidden()
                    }
                }
                .padding(8)
            }

            HStack {
                Button(L10n.uploadSaveCredential) { saveSecret() }
                Button(L10n.uploadTest) { runTestUpload() }.disabled(service.isUploading)
                Button(L10n.uploadResetConfiguration, role: .destructive) { resetConfiguration() }
                if service.isUploading {
                    ProgressView(value: Double(service.progress?.sentBytes ?? 0), total: Double(max(1, service.progress?.totalBytes ?? 1)))
                    Button(L10n.actionCancel) { service.cancel() }
                }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var uploadPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L10n.uploadLinkFormat, selection: $settings.linkFormat) {
                Text(L10n.uploadLinkFormatURL).tag(LinkFormat.url)
                Text(L10n.uploadLinkFormatMarkdown).tag(LinkFormat.markdown)
                Text(L10n.uploadLinkFormatHTML).tag(LinkFormat.html)
            }.pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text(L10n.uploadHistoryLimit)
                    TextField("", value: $settings.historyLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L10n.uploadMaximumFileSize)
                    TextField("", value: $settings.maximumFileSizeMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PreferenceHotkeyRecorderRow(
                title: L10n.uploadHotkey,
                subtitle: L10n.uploadHotkeySubtitle,
                symbol: "arrow.up.circle",
                theme: theme,
                keyCode: settings.uploadHotkeyKeyCode,
                modifiers: settings.uploadHotkeyModifiers
            ) { keyCode, modifiers in
                settings.uploadHotkeyKeyCode = keyCode
                settings.uploadHotkeyModifiers = modifiers
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            UploadHistoryView(
                store: service.historyStore,
                sourceName: { entry in
                    settings.s3Configuration(id: entry.backendConfigID)?.name
                },
                onCopy: { entry in
                    Task {
                        do { _ = try await service.copyLink(for: entry); message = L10n.uploadCopied }
                        catch { message = error.localizedDescription }
                    }
                },
                onDelete: { entry, deleteRemote in
                    try await service.removeHistoryEntry(entry, deleteRemoteObject: deleteRemote)
                },
                onClear: { deleteRemote in
                    try await service.removeAllHistory(deleteRemoteObjects: deleteRemote)
                }
            )
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        GridRow {
            Text(title)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var endpointField: some View {
        GridRow {
            Text(L10n.uploadEndpoint)
            TextField(endpointPlaceholder, text: $settings.s3.endpoint)
                .textFieldStyle(.roundedBorder)
                .disabled(preset == .aws)
        }
    }

    private var regionField: some View {
        GridRow {
            Text(L10n.uploadRegion)
            TextField("", text: $settings.s3.region)
                .textFieldStyle(.roundedBorder)
                .disabled(preset == .r2)
        }
    }

    private var endpointPlaceholder: String {
        switch preset {
        case .aws: return L10n.uploadEndpointAWSAutomatic
        case .r2: return "https://<account-id>.r2.cloudflarestorage.com"
        case .minio: return "https://minio.example.com"
        case .custom: return "https://s3.example.com"
        }
    }

    private func saveSecret() {
        let configID = settings.s3.id
        do { try service.saveSecret(secret, for: configID); message = L10n.uploadCredentialSaved }
        catch { message = error.localizedDescription }
    }

    private func loadSelectedConfiguration() {
        let configID = settings.s3.id
        do {
            secret = try service.loadSecret(for: configID) ?? ""
            message = ""
        } catch {
            secret = ""
            message = error.localizedDescription
        }
        preset = inferredPreset
    }

    private func addConfiguration() {
        var config = S3Config()
        config.name = String(format: L10n.uploadNewConfigurationName, settings.s3Configurations.count + 1)
        settings.s3Configurations.append(config)
        settings.selectedS3ConfigID = config.id
        loadSelectedConfiguration()
    }

    private func deleteSelectedConfiguration() {
        guard settings.s3Configurations.count > 1 else { return }
        let deletedID = settings.selectedS3ConfigID
        guard let index = settings.s3Configurations.firstIndex(where: { $0.id == deletedID }) else { return }
        settings.s3Configurations.remove(at: index)
        settings.selectedS3ConfigID = settings.s3Configurations[min(index, settings.s3Configurations.count - 1)].id
        loadSelectedConfiguration()
        Task {
            do {
                try await service.deleteCredential(for: deletedID)
                message = L10n.uploadConfigurationDeleted
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func runTestUpload() {
        let configID = settings.s3.id
        do {
            try service.saveSecret(secret, for: configID)
        } catch {
            message = error.localizedDescription
            return
        }
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("meow-upload-test-\(UUID().uuidString).txt")
                    try Data("Meow file upload test".utf8).write(to: url, options: .atomic)
                    return url
                }.value
                defer { try? FileManager.default.removeItem(at: url) }
                _ = try await service.testUpload(fileURL: url)
                message = L10n.uploadSucceeded
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func applyPreset(_ value: S3Preset) {
        var config = settings.s3
        switch value {
        case .aws:
            config.endpoint = ""
            config.region = "us-east-1"
            config.urlStyle = .virtualHosted
        case .r2:
            config.region = "auto"
            config.urlStyle = .path
        case .minio:
            config.region = "us-east-1"
            config.urlStyle = .path
        case .custom:
            return
        }
        settings.s3 = config
    }

    private var inferredPreset: S3Preset {
        if settings.s3.endpoint.isEmpty, settings.s3.urlStyle == .virtualHosted { return .aws }
        if settings.s3.region == "auto" { return .r2 }
        if settings.s3.region == "us-east-1", settings.s3.urlStyle == .path { return .minio }
        return .custom
    }

    private func resetConfiguration() {
        let oldID = settings.s3.id
        let oldName = settings.s3.name
        Task {
            do {
                try await service.deleteCredential(for: oldID)
                var replacement = S3Config()
                replacement.name = oldName
                if let index = settings.s3Configurations.firstIndex(where: { $0.id == oldID }) {
                    settings.s3Configurations[index] = replacement
                }
                settings.selectedS3ConfigID = replacement.id
                secret = ""
                preset = .custom
                message = L10n.uploadConfigurationReset
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
