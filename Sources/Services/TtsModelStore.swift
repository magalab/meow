import AppKit
import Foundation

enum TtsModelState: Equatable, Sendable {
    case notInstalled
    case downloading(Double)
    case installed
    case failed(String)
}

/// Compatibility facade for the former downloadable TTS model store.
///
/// TTS currently uses the voices shipped with macOS, so there is no model
/// archive to download or retain. Keeping this small facade lets existing
/// preferences and view wiring migrate without reintroducing the removed
/// runtime or its model files.
@MainActor
final class TtsModelStore: ObservableObject {
    @Published private(set) var state: TtsModelState = .installed
    @Published private(set) var selectedModel: TtsModelKind = .system

    let modelsRootDirectory: URL

    init(fileManager: FileManager = .default, modelsRootDirectory: URL? = nil) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        self.modelsRootDirectory = modelsRootDirectory ?? appSupport
            .appendingPathComponent("Meow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("TTS", isDirectory: true)
    }

    var modelDirectory: URL {
        modelsRootDirectory.appendingPathComponent(selectedModel.storageDirectoryName, isDirectory: true)
    }

    var isInstalled: Bool {
        true
    }

    func apply(selectedModel: TtsModelKind) {
        self.selectedModel = selectedModel
        state = .installed
    }

    func refreshState() {
        state = .installed
    }

    func downloadModel() {
        state = .installed
    }

    func cancelDownload() {
        state = .installed
    }

    func deleteModel() {
        state = .installed
    }

    func openModelFolder() {
        NSWorkspace.shared.open(modelsRootDirectory)
    }

    func configurationDirectory(for model: TtsModelKind) -> URL? {
        modelsRootDirectory.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    }
}
