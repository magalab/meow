import AppKit
import Foundation

final class ClipboardImageCache {
    static let shared = ClipboardImageCache()

    private let cacheDir: URL
    private let maxImageDimension: CGFloat = 2048

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("Meow/Clipboard", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func saveImage(_ image: NSImage, sourceName: String = "Screenshot") -> ImageClipboardContent? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Generate thumbnail
        let thumbnailSize = NSSize(width: 100, height: 100)
        let thumbnail = image.resized(to: thumbnailSize)

        let fileURLs = makeImageFileURLs(
            sourceName: sourceName,
            defaultName: "Screenshot",
            fallbackExtension: "png"
        )
        let originalPath = fileURLs.original
        let thumbnailPath = fileURLs.thumbnail

        // Save thumbnail
        guard let thumbnailData = thumbnail.pngData() else { return nil }
        try? thumbnailData.write(to: thumbnailPath)

        // Save original if not too large, as PNG (screenshots don't have original format)
        if width <= Int(maxImageDimension), height <= Int(maxImageDimension) {
            if let originalData = image.pngData() {
                try? originalData.write(to: originalPath)
            }
        }

        return ImageClipboardContent(
            thumbnailPath: thumbnailPath.path,
            originalPath: width <= Int(maxImageDimension) && height <= Int(maxImageDimension) ? originalPath.path : nil,
            sourceName: sourceName,
            width: width,
            height: height
        )
    }

    /// Saves image preserving original file format
    func saveImageFromFile(data: Data, sourceName: String, image: NSImage) -> ImageClipboardContent? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Generate thumbnail (always PNG for thumbnails)
        let thumbnailSize = NSSize(width: 100, height: 100)
        let thumbnail = image.resized(to: thumbnailSize)

        let fileURLs = makeImageFileURLs(
            sourceName: sourceName,
            defaultName: "ClipboardImage"
        )
        let originalPath = fileURLs.original
        let thumbnailPath = fileURLs.thumbnail

        // Save thumbnail
        if let thumbnailData = thumbnail.pngData() {
            try? thumbnailData.write(to: thumbnailPath)
        }

        // Save original with correct format
        if width <= Int(maxImageDimension), height <= Int(maxImageDimension) {
            try? data.write(to: originalPath)
        }

        return ImageClipboardContent(
            thumbnailPath: thumbnailPath.path,
            originalPath: width <= Int(maxImageDimension) && height <= Int(maxImageDimension) ? originalPath.path : nil,
            sourceName: sourceName,
            width: width,
            height: height
        )
    }

    func loadImage(from path: String) -> NSImage? {
        return NSImage(contentsOfFile: path)
    }

    func cleanupOldFiles() {
        // Clean up orphaned files periodically
        let contents = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        // Keep recent 100 files
        let sorted = contents.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }

        for url in sorted.dropFirst(100) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makeImageFileURLs(
        sourceName: String,
        defaultName: String,
        fallbackExtension: String? = nil
    ) -> (original: URL, thumbnail: URL) {
        let sourceURL = URL(fileURLWithPath: sourceName)
        let baseName = resolvedBaseName(sourceURL, defaultName: defaultName)
        let originalExtension = resolvedExtension(sourceURL, fallback: fallbackExtension)
        let uniqueSuffix = UUID().uuidString.lowercased()

        let originalFileName: String
        if let originalExtension {
            originalFileName = "\(baseName)-\(uniqueSuffix).\(originalExtension)"
        } else {
            originalFileName = "\(baseName)-\(uniqueSuffix)"
        }

        let thumbnailFileName = "\(baseName)-\(uniqueSuffix)_thumb.png"
        return (
            cacheDir.appendingPathComponent(originalFileName),
            cacheDir.appendingPathComponent(thumbnailFileName)
        )
    }

    private func resolvedBaseName(_ sourceURL: URL, defaultName: String) -> String {
        let candidate = sourceURL.deletingPathExtension().lastPathComponent
        let sanitized = sanitizeFileName(candidate)
        return sanitized.isEmpty ? defaultName : sanitized
    }

    private func resolvedExtension(_ sourceURL: URL, fallback: String? = nil) -> String? {
        let ext = sanitizeFileExtension(sourceURL.pathExtension)
        if !ext.isEmpty {
            return ext
        }
        if let fallback {
            let sanitizedFallback = sanitizeFileExtension(fallback)
            return sanitizedFallback.isEmpty ? nil : sanitizedFallback
        }
        return nil
    }

    private func sanitizeFileName(_ name: String) -> String {
        let replaced = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeFileExtension(_ ext: String) -> String {
        let sanitized = ext.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: "",
            options: .regularExpression
        )
        return sanitized.lowercased()
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    func resized(to newSize: NSSize) -> NSImage {
        let aspectRatio = size.width / size.height
        var targetSize = newSize

        if size.width > size.height {
            targetSize.height = newSize.width / aspectRatio
        } else {
            targetSize.width = newSize.height * aspectRatio
        }

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

final class ClipboardStore {
    private static let maxEntries = 50
    private static let maxTextLength = 100_000

    private var entries: [ClipboardEntry] = []
    private var lastChangeCount: Int = 0
    private var monitorTimer: Timer?
    private var onChange: (() -> Void)?

    func startMonitoring(onChange: @escaping () -> Void) {
        stopMonitoring()
        self.onChange = onChange
        lastChangeCount = NSPasteboard.general.changeCount

        // Clean up old cache files on launch
        ClipboardImageCache.shared.cleanupOldFiles()

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func getEntries() -> [ClipboardEntry] {
        return entries
    }

    /// Tries to read an image from the pasteboard using multiple format checks.
    private func getImageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        // Try TIFF data
        if let data = pasteboard.data(forType: .tiff),
           let image = NSImage(data: data)
        {
            return image
        }

        // Try PNG data
        if let data = pasteboard.data(forType: .png),
           let image = NSImage(data: data)
        {
            return image
        }

        // Try reading as file URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first
        {
            let image = NSImage(contentsOf: url)
            if image != nil {
                return image
            }
        }

        // Try reading directly as NSImage from pasteboard
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        return nil
    }

    func delete(_ entry: ClipboardEntry) {
        // Clean up disk cache for image/audio entries
        if case let .image(imageContent) = entry.content {
            try? FileManager.default.removeItem(atPath: imageContent.thumbnailPath)
            if let originalPath = imageContent.originalPath {
                try? FileManager.default.removeItem(atPath: originalPath)
            }
        } else if case let .audio(audioContent) = entry.content {
            try? FileManager.default.removeItem(atPath: audioContent.cachePath)
        }
        entries.removeAll { $0.id == entry.id }
        onChange?()
    }

    func writeToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.content {
        case let .text(string):
            pasteboard.setString(string, forType: .string)

        case let .url(url):
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.writeObjects([url as NSURL])

        case let .file(fileContent):
            pasteboard.writeObjects([fileContent.url as NSURL])

        case let .image(imageContent):
            // Write image as TIFF data (most apps support this)
            if let originalPath = imageContent.originalPath,
               let image = NSImage(contentsOfFile: originalPath),
               let tiffData = image.tiffRepresentation
            {
                pasteboard.setData(tiffData, forType: .tiff)
                // Also write file URL for apps that prefer file promises
                pasteboard.writeObjects([URL(fileURLWithPath: originalPath) as NSURL])
            } else if let image = NSImage(contentsOfFile: imageContent.thumbnailPath),
                      let tiffData = image.tiffRepresentation
            {
                pasteboard.setData(tiffData, forType: .tiff)
            }

        case let .audio(audioContent):
            let url = URL(fileURLWithPath: audioContent.cachePath)
            pasteboard.writeObjects([url as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for file URL first (from Finder file copy)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first
        {
            // Check if it's a URL (web URL)
            if firstURL.scheme == "http" || firstURL.scheme == "https" {
                let entry = ClipboardEntry(
                    id: UUID().uuidString,
                    content: .url(firstURL),
                    copiedAt: Date()
                )
                addEntry(entry)
                return
            }

            // It's a file - check if it's an image by extension first
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "ico"]
            let ext = firstURL.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                // Read original file data directly to preserve format
                if let fileData = try? Data(contentsOf: firstURL),
                   let image = NSImage(contentsOf: firstURL)
                {
                    if let imageContent = ClipboardImageCache.shared.saveImageFromFile(
                        data: fileData,
                        sourceName: firstURL.lastPathComponent,
                        image: image
                    ) {
                        let entry = ClipboardEntry(
                            id: UUID().uuidString,
                            content: .image(imageContent),
                            copiedAt: Date()
                        )
                        addEntry(entry)
                        return
                    }
                }
            }

            // Not an image file, store as regular file
            let fileContent = FileClipboardContent(url: firstURL, name: firstURL.lastPathComponent)
            let entry = ClipboardEntry(
                id: UUID().uuidString,
                content: .file(fileContent),
                copiedAt: Date()
            )
            addEntry(entry)
            return
        }

        // Try to read files via pasteboardItems (handles some file promise cases)
        if let items = pasteboard.pasteboardItems {
            for item in items {
                let urlTypes = ["public.file-url"]
                for typeString in urlTypes {
                    let type = NSPasteboard.PasteboardType(typeString)
                    guard let data = item.data(forType: type),
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString)
                    else {
                        continue
                    }

                    let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "ico"]
                    let ext = url.pathExtension.lowercased()
                    if imageExtensions.contains(ext),
                       let fileData = try? Data(contentsOf: url),
                       let image = NSImage(contentsOf: url)
                    {
                        if let imageContent = ClipboardImageCache.shared.saveImageFromFile(
                            data: fileData,
                            sourceName: url.lastPathComponent,
                            image: image
                        ) {
                            let entry = ClipboardEntry(
                                id: UUID().uuidString,
                                content: .image(imageContent),
                                copiedAt: Date()
                            )
                            addEntry(entry)
                            return
                        }
                    }
                    let fileContent = FileClipboardContent(url: url, name: url.lastPathComponent)
                    let entry = ClipboardEntry(
                        id: UUID().uuidString,
                        content: .file(fileContent),
                        copiedAt: Date()
                    )
                    addEntry(entry)
                    return
                }
            }
        }

        // Check for image data (TIFF, PNG) - this catches screenshots and app-copied images
        if let image = getImageFromPasteboard(pasteboard) {
            if let imageContent = ClipboardImageCache.shared.saveImage(image) {
                let entry = ClipboardEntry(
                    id: UUID().uuidString,
                    content: .image(imageContent),
                    copiedAt: Date()
                )
                addEntry(entry)
            }
            return
        }

        // Check for text
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Avoid recording our own writes
            if let last = entries.first,
               case let .text(lastText) = last.content,
               lastText == trimmed
            {
                return
            }

            let content = trimmed.count > Self.maxTextLength
                ? String(trimmed.prefix(Self.maxTextLength))
                : trimmed

            let entry = ClipboardEntry(
                id: UUID().uuidString,
                content: .text(content),
                copiedAt: Date()
            )
            addEntry(entry)
        }
    }

    private func addEntry(_ entry: ClipboardEntry) {
        // Remove duplicate if same content exists
        entries.removeAll { $0.content == entry.content }

        entries.insert(entry, at: 0)

        if entries.count > Self.maxEntries {
            let removed = entries.removeLast()
            // Clean up removed entry's disk cache
            if case let .image(imageContent) = removed.content {
                try? FileManager.default.removeItem(atPath: imageContent.thumbnailPath)
                if let originalPath = imageContent.originalPath {
                    try? FileManager.default.removeItem(atPath: originalPath)
                }
            }
        }

        onChange?()
    }
}
