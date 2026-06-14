import AppKit
@preconcurrency import AVFoundation
import Foundation

@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var artifacts: [RecordingArtifact] = []

    private let fileManager: FileManager
    private let storageDirectory: URL
    private let thumbnailDirectory: URL
    private let metadataURL: URL
    private let recoveryDirectory: URL

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        let support = storageDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Meow/Recordings", isDirectory: true)
        self.storageDirectory = support
        thumbnailDirectory = support.appendingPathComponent("Thumbnails", isDirectory: true)
        metadataURL = support.appendingPathComponent("index.json")
        recoveryDirectory = support.appendingPathComponent("Recovery", isDirectory: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        load()
        Task { await recoverInterruptedRecordings() }
    }

    func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([RecordingArtifact].self, from: data)
        else {
            artifacts = []
            return
        }
        artifacts = decoded
            .filter { fileManager.fileExists(atPath: $0.fileURL.path) }
            .sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    func add(
        fileURL: URL,
        source: RecordingSourceKind,
        duration: TimeInterval,
        width: Int,
        height: Int,
        codec: RecordingVideoCodec?,
        hasSystemAudio: Bool,
        hasMicrophoneAudio: Bool
    ) async -> RecordingArtifact {
        let id = UUID()
        let thumbnailURL = await createThumbnail(for: fileURL, id: id)
        let size = Self.fileSize(at: fileURL, fileManager: fileManager)
        let artifact = RecordingArtifact(
            id: id,
            source: source,
            createdAt: Date(),
            duration: duration,
            fileURL: fileURL,
            thumbnailURL: thumbnailURL,
            width: width,
            height: height,
            fileSize: size,
            videoCodec: codec,
            hasSystemAudio: hasSystemAudio,
            hasMicrophoneAudio: hasMicrophoneAudio
        )
        artifacts.insert(artifact, at: 0)
        persist()
        return artifact
    }

    func markRecordingStarted(fileURL: URL, source: RecordingSourceKind) {
        let record = RecordingRecoveryRecord(
            id: UUID(),
            fileURL: fileURL,
            source: source,
            startedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        let url = recoveryDirectory.appendingPathComponent("\(record.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    func markRecordingFinished(fileURL: URL) {
        for url in recoveryRecordURLs() {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(RecordingRecoveryRecord.self, from: data),
                  record.fileURL.standardizedFileURL == fileURL.standardizedFileURL
            else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    func delete(_ artifact: RecordingArtifact, deleteFile: Bool = true) {
        artifacts.removeAll { $0.id == artifact.id }
        if deleteFile {
            try? fileManager.removeItem(at: artifact.fileURL)
        }
        if let thumbnailURL = artifact.thumbnailURL {
            try? fileManager.removeItem(at: thumbnailURL)
        }
        persist()
    }

    func clear(deleteFiles: Bool = true) {
        let existing = artifacts
        artifacts = []
        for artifact in existing {
            if deleteFiles {
                try? fileManager.removeItem(at: artifact.fileURL)
            }
            if let thumbnailURL = artifact.thumbnailURL {
                try? fileManager.removeItem(at: thumbnailURL)
            }
        }
        persist()
    }

    func applyRetentionPolicy(historyLimit: Int, retentionDays: Int, maxStorageMB: Int) {
        let retained = Self.retainedArtifactIDs(
            artifacts,
            historyLimit: historyLimit,
            retentionDays: retentionDays,
            maxStorageBytes: maxStorageMB > 0 ? Int64(maxStorageMB) * 1_024 * 1_024 : nil
        )
        for artifact in artifacts where !retained.contains(artifact.id) {
            delete(artifact)
        }
    }

    static func retainedArtifactIDs(
        _ artifacts: [RecordingArtifact],
        historyLimit: Int,
        retentionDays: Int,
        maxStorageBytes: Int64?,
        now: Date = Date()
    ) -> Set<UUID> {
        let sorted = artifacts.sorted { $0.createdAt > $1.createdAt }
        let cutoff = retentionDays > 0
            ? now.addingTimeInterval(-TimeInterval(retentionDays) * 86_400)
            : nil
        var retained: [RecordingArtifact] = []
        var bytes: Int64 = 0

        for artifact in sorted {
            if historyLimit > 0, retained.count >= historyLimit { break }
            if let cutoff, artifact.createdAt < cutoff { continue }
            if let maxStorageBytes,
               !retained.isEmpty,
               bytes + artifact.fileSize > maxStorageBytes
            {
                continue
            }
            retained.append(artifact)
            bytes += artifact.fileSize
        }
        return Set(retained.map(\.id))
    }

    static func expandedFileName(template: String, date: Date = Date()) -> String {
        var result = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty {
            result = RecordingSettings.default.fileNameTemplate
        }
        let tokens = ["yyyy", "MM", "dd", "HH", "mm", "ss"]
        for token in tokens {
            let formatter = DateFormatter()
            formatter.dateFormat = token
            result = result.replacingOccurrences(of: token, with: formatter.string(from: date))
        }
        return result
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func outputURL(
        settings: RecordingSettings,
        source: RecordingSourceKind? = nil,
        date: Date = Date()
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory: URL
        if settings.saveDirectory.isEmpty {
            directory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Meow", isDirectory: true)
        } else {
            directory = URL(fileURLWithPath: NSString(string: settings.saveDirectory).expandingTildeInPath)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = expandedFileName(template: settings.fileNameTemplate, date: date)
        let fileExtension: String
        switch source {
        case .systemAudio:
            fileExtension = settings.audioFormat.fileExtension
        case .mobileDevice:
            fileExtension = RecordingVideoFormat.mov.fileExtension
        default:
            fileExtension = settings.videoFormat.fileExtension
        }
        var candidate = directory.appendingPathComponent(base)
            .appendingPathExtension(fileExtension)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }

    static func availableCapacity(at directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        return values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(artifacts) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func recoverInterruptedRecordings() async {
        let indexed = Set(artifacts.map { $0.fileURL.standardizedFileURL })
        for manifestURL in recoveryRecordURLs() {
            guard let data = try? Data(contentsOf: manifestURL),
                  let record = try? JSONDecoder().decode(RecordingRecoveryRecord.self, from: data)
            else {
                try? fileManager.removeItem(at: manifestURL)
                continue
            }
            let fileURL = record.fileURL.standardizedFileURL
            guard fileManager.fileExists(atPath: fileURL.path) else {
                try? fileManager.removeItem(at: manifestURL)
                continue
            }
            if indexed.contains(fileURL) {
                try? fileManager.removeItem(at: manifestURL)
                continue
            }

            let asset = AVURLAsset(url: fileURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            guard duration > 0 else { continue }
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let size = (try? await videoTracks.first?.load(.naturalSize)) ?? .zero
            _ = await add(
                fileURL: fileURL,
                source: record.source,
                duration: duration,
                width: Int(abs(size.width)),
                height: Int(abs(size.height)),
                codec: nil,
                hasSystemAudio: !audioTracks.isEmpty,
                hasMicrophoneAudio: false
            )
            try? fileManager.removeItem(at: manifestURL)
        }
    }

    private func recoveryRecordURLs() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    private func createThumbnail(for fileURL: URL, id: UUID) async -> URL? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        do {
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let thumbnailSecond = duration.isFinite && duration > 1
                ? min(max(0.2, duration * 0.2), max(0.2, duration - 0.2))
                : 0.1
            let image = try await generator.image(
                at: CMTime(seconds: thumbnailSecond, preferredTimescale: 600)
            ).image
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
                return nil
            }
            let url = thumbnailDirectory.appendingPathComponent("\(id.uuidString.lowercased()).jpg")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private struct RecordingRecoveryRecord: Codable {
    let id: UUID
    let fileURL: URL
    let source: RecordingSourceKind
    let startedAt: Date
}
