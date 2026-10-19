import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Safe to share across detached clipboard tasks: configuration is immutable,
// each operation uses UUID-based file names, and writes target separate files.
public final class ClipboardImageCache: @unchecked Sendable {
    public static let shared = ClipboardImageCache()

    private let pendingImagesDirectory: URL
    private let maxImageDimension = 4096
    private let maxOriginalBytes = 64 * 1_024 * 1_024

    private init(directory: URL = ClipboardStoragePaths.defaultDirectory) {
        pendingImagesDirectory = directory.appendingPathComponent("pending-images", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: pendingImagesDirectory,
            withIntermediateDirectories: true
        )
    }

    public func saveImageData(
        _ data: Data,
        sourceName: String = "Screenshot",
        preserveOriginalFormat: Bool = false
    ) -> ImageClipboardContent? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ), let thumbnailData = pngData(for: thumbnail)
        else { return nil }

        let fileURLs = makeImageFileURLs(
            sourceName: sourceName,
            fallbackExtension: preserveOriginalFormat ? nil : "png"
        )
        do {
            try thumbnailData.write(to: fileURLs.thumbnail, options: .atomic)
        } catch {
            return nil
        }

        let canStoreOriginal = width <= maxImageDimension
            && height <= maxImageDimension
            && data.count <= maxOriginalBytes
        var originalPath: String?
        if canStoreOriginal {
            let originalData = preserveOriginalFormat ? data : (pngData(for: cgImage) ?? data)
            do {
                try originalData.write(to: fileURLs.original, options: .atomic)
                originalPath = fileURLs.original.path
            } catch {
                originalPath = nil
            }
        }

        return ImageClipboardContent(
            thumbnailPath: fileURLs.thumbnail.path,
            originalPath: originalPath,
            sourceName: sourceName,
            width: width,
            height: height,
            contentHash: ClipboardContent.sha256(data)
        )
    }

    private func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func makeImageFileURLs(
        sourceName: String,
        fallbackExtension: String?
    ) -> (original: URL, thumbnail: URL) {
        let sourceURL = URL(fileURLWithPath: sourceName)
        let candidate = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = sanitizeFileName(candidate).isEmpty
            ? "ClipboardImage"
            : sanitizeFileName(candidate)
        let sourceExtension = sanitizeFileExtension(sourceURL.pathExtension)
        let resolvedExtension = sourceExtension.isEmpty ? fallbackExtension : sourceExtension
        let suffix = UUID().uuidString.lowercased()
        let originalName = resolvedExtension.map { "\(baseName)-\(suffix).\($0)" }
            ?? "\(baseName)-\(suffix)"
        return (
            pendingImagesDirectory.appendingPathComponent(originalName),
            pendingImagesDirectory.appendingPathComponent("\(baseName)-\(suffix)_thumb.png")
        )
    }

    private func sanitizeFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeFileExtension(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: "",
            options: .regularExpression
        ).lowercased()
    }
}
