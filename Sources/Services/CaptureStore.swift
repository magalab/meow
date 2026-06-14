import AppKit
import Foundation

enum CaptureStoreError: LocalizedError {
    case imageEncodingFailed

    var errorDescription: String? {
        L10n.screenshotErrorEncoding
    }
}

@MainActor
final class CaptureStore: ObservableObject {
    private let fileManager: FileManager
    private let capturesDirectory: URL
    private let metadataURL: URL
    @Published private(set) var artifacts: [CaptureArtifact] = []
    var onArtifactsRemoved: ((Set<UUID>) -> Void)?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        capturesDirectory = support
            .appendingPathComponent("Meow", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        metadataURL = capturesDirectory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        load()
    }

    func saveInternal(
        image: CGImage,
        kind: CaptureArtifactKind,
        historyLimit: Int = 100,
        retentionDays: Int = 0,
        maxStorageMB: Int = 0
    ) throws -> CaptureArtifact {
        let id = UUID()
        let imageURL = capturesDirectory.appendingPathComponent("\(id.uuidString.lowercased()).png")
        let thumbnailURL = capturesDirectory.appendingPathComponent("\(id.uuidString.lowercased())-thumb.png")
        let imageData = try encodedData(image: image, format: .png, jpegQuality: 1)
        try imageData.write(to: imageURL, options: .atomic)

        do {
            let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                .resized(to: NSSize(width: 240, height: 240))
            guard let thumbnailData = thumbnail.pngData() else {
                throw CaptureStoreError.imageEncodingFailed
            }
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }

        let artifact = CaptureArtifact(
            id: id,
            kind: kind,
            createdAt: Date(),
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            width: image.width,
            height: image.height
        )
        artifacts.insert(artifact, at: 0)
        applyRetentionPolicy(
            historyLimit: historyLimit,
            retentionDays: retentionDays,
            maxStorageMB: maxStorageMB
        )
        persist()
        return artifact
    }

    func applyRetention(
        historyLimit: Int,
        retentionDays: Int,
        maxStorageMB: Int
    ) {
        applyRetentionPolicy(
            historyLimit: historyLimit,
            retentionDays: retentionDays,
            maxStorageMB: maxStorageMB
        )
        persist()
    }

    func updateOCRText(_ text: String, for id: UUID) {
        guard let index = artifacts.firstIndex(where: { $0.id == id }) else { return }
        let sanitized = Self.sanitizedOCRText(text)
        artifacts[index].ocrText = sanitized.isEmpty ? nil : sanitized
        persist()
    }

    static func sanitizedOCRText(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.lowercased().contains("otpauth://") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveExternal(
        image: CGImage,
        settings: ScreenshotSettings,
        createdAt: Date = Date()
    ) throws -> URL {
        let directory = resolvedSaveDirectory(settings.saveDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = Self.expandedFileName(template: settings.fileNameTemplate, date: createdAt)
        let uniqueURL = uniqueFileURL(
            directory: directory,
            baseName: baseName,
            extension: settings.imageFormat.fileExtension
        )
        let data = try encodedData(
            image: image,
            format: settings.imageFormat,
            jpegQuality: settings.jpegQuality
        )
        try data.write(to: uniqueURL, options: .atomic)
        return uniqueURL
    }

    func delete(_ artifact: CaptureArtifact) {
        artifacts.removeAll { $0.id == artifact.id }
        try? fileManager.removeItem(at: artifact.imageURL)
        try? fileManager.removeItem(at: artifact.thumbnailURL)
        persist()
    }

    func clear() {
        for artifact in artifacts {
            try? fileManager.removeItem(at: artifact.imageURL)
            try? fileManager.removeItem(at: artifact.thumbnailURL)
        }
        artifacts.removeAll()
        persist()
    }

    static func expandedFileName(template: String, date: Date) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? ScreenshotSettings.default.fileNameTemplate : trimmed
        let tokenFormats = [
            ("yyyy", "yyyy"),
            ("MM", "MM"),
            ("dd", "dd"),
            ("HH", "HH"),
            ("mm", "mm"),
            ("ss", "ss"),
        ]
        var expanded = source
        for (token, format) in tokenFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            expanded = expanded.replacingOccurrences(of: token, with: formatter.string(from: date))
        }

        let invalid = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let parts = expanded.components(separatedBy: invalid)
        let sanitized = parts
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Meow Screenshot" : sanitized
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([CaptureArtifact].self, from: data)
        else { return }
        artifacts = decoded.filter {
            fileManager.fileExists(atPath: $0.imageURL.path) &&
                fileManager.fileExists(atPath: $0.thumbnailURL.path)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(artifacts) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func applyRetentionPolicy(
        historyLimit: Int,
        retentionDays: Int,
        maxStorageMB: Int,
        now: Date = Date()
    ) {
        let retainedIDs = Self.retainedArtifactIDs(
            artifacts,
            historyLimit: historyLimit,
            retentionDays: retentionDays,
            maxStorageBytes: maxStorageMB > 0
                ? Int64(maxStorageMB) * 1_024 * 1_024
                : nil,
            now: now,
            diskUsage: diskUsage
        )
        let retained = artifacts.filter { retainedIDs.contains($0.id) }
        let removed = artifacts.filter { !retainedIDs.contains($0.id) }
        guard !removed.isEmpty else { return }
        artifacts = retained
        for artifact in removed {
            try? fileManager.removeItem(at: artifact.imageURL)
            try? fileManager.removeItem(at: artifact.thumbnailURL)
        }
        onArtifactsRemoved?(Set(removed.map(\.id)))
    }

    private func diskUsage(of artifact: CaptureArtifact) -> Int64 {
        [artifact.imageURL, artifact.thumbnailURL].reduce(into: 0) { total, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
    }

    static func retainedArtifactIDs(
        _ artifacts: [CaptureArtifact],
        historyLimit: Int,
        retentionDays: Int,
        maxStorageBytes: Int64?,
        now: Date,
        diskUsage: (CaptureArtifact) -> Int64
    ) -> Set<UUID> {
        let boundedLimit = min(max(historyLimit, 10), 500)
        var retained = artifacts

        if retentionDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)
        {
            retained.removeAll { $0.createdAt < cutoff }
        }

        retained = Array(retained.prefix(boundedLimit))

        if let maxStorageBytes, maxStorageBytes > 0 {
            var storedBytes: Int64 = 0
            retained = retained.enumerated().compactMap { index, artifact in
                let artifactBytes = diskUsage(artifact)
                if index == 0 {
                    storedBytes = artifactBytes
                    return artifact
                }
                guard storedBytes + artifactBytes <= maxStorageBytes else {
                    return nil
                }
                storedBytes += artifactBytes
                return artifact
            }
        }

        return Set(retained.map(\.id))
    }

    private func resolvedSaveDirectory(_ configuredPath: String) -> URL {
        let expanded = NSString(string: configuredPath).expandingTildeInPath
        if !expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return pictures.appendingPathComponent("Meow", isDirectory: true)
    }

    private func uniqueFileURL(directory: URL, baseName: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }

    private func encodedData(
        image: CGImage,
        format: ScreenshotImageFormat,
        jpegQuality: Double
    ) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data: Data?
        switch format {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            data = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegQuality.clamped(to: 0.1...1)]
            )
        }
        guard let data else { throw CaptureStoreError.imageEncodingFailed }
        return data
    }
}
