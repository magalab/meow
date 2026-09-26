import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao

@Test("SenseVoice downloads accept the CoreML model staging layout")
func senseVoiceDownloadStagingValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-ASR-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for relativePath in SpeechModelKind.senseVoice.requiredRelativePaths {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: fileURL)
    }

    try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)

    try FileManager.default.removeItem(
        at: root.appendingPathComponent("vocab.json")
    )
    #expect(throws: (any Error).self) {
        try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)
    }
}

@Test("Speech model recovery restores a valid backup after an interrupted install")
func speechModelRecoveryRestoresBackup() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-ASR-Recovery-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let backup = root.appendingPathComponent(
        ".\(SpeechModelKind.senseVoice.storageDirectoryName)-backup-test",
        isDirectory: true
    )
    for relativePath in SpeechModelKind.senseVoice.requiredRelativePaths {
        let fileURL = backup.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: fileURL)
    }

    SpeechModelStore.reconcileOrphanedBackups(at: root)

    let target = root.appendingPathComponent(
        SpeechModelKind.senseVoice.storageDirectoryName,
        isDirectory: true
    )
    #expect(FileManager.default.fileExists(atPath: target.path))
    #expect(!FileManager.default.fileExists(atPath: backup.path))
}

@Test("Legacy speech model settings migrate to SenseVoice")
func legacySpeechModelSettingMigration() throws {
    let settings = try JSONDecoder().decode(
        SpeechSettings.self,
        from: Data("{\"model\":\"parakeetEnglish\"}".utf8)
    )

    #expect(settings.model == .senseVoice)
}

@Test("SenseVoice manifest is pinned and has unique verified artifacts")
func senseVoiceManifestIsPinned() {
    let artifacts = SpeechModelKind.senseVoice.manifest.artifacts
    #expect(SpeechModelKind.senseVoice.manifest.version.count == 40)
    #expect(Set(artifacts.map(\.relativePath)).count == artifacts.count)
    #expect(artifacts.allSatisfy { $0.sha256.count == 64 })
    #expect(artifacts.allSatisfy { $0.remoteURL.absoluteString.contains("/resolve/") })
}

#endif
