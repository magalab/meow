import CryptoKit
import Foundation

struct ClipboardEntry: Identifiable, Hashable, Sendable {
    let id: String
    let content: ClipboardContent
    let copiedAt: Date
    let sourceBundleID: String?
    let pinnedAt: Date?

    init(
        id: String,
        content: ClipboardContent,
        copiedAt: Date,
        sourceBundleID: String? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    func with(copiedAt: Date? = nil, pinnedAt: Date?) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            copiedAt: copiedAt ?? self.copiedAt,
            sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt
        )
    }

    var preview: String {
        content.preview
    }

    var symbolName: String {
        content.symbolName
    }
}

enum ClipboardContent: Hashable, Sendable {
    case text(String)
    case image(ImageClipboardContent)
    case file(FileClipboardContent)
    case url(URL)
    case audio(AudioClipboardContent)

    var preview: String {
        switch self {
        case let .text(string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count <= 50 {
                return singleLine
            }
            let index = singleLine.index(singleLine.startIndex, offsetBy: 50)
            return String(singleLine[..<index]) + "…"
        case let .image(image):
            return image.previewText
        case let .file(file):
            return file.url.lastPathComponent
        case let .url(url):
            return url.absoluteString
        case let .audio(audio):
            return audio.name
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        case .audio:
            return "waveform"
        }
    }

    var aiContextText: String {
        switch self {
        case let .text(string):
            return string
        case let .image(image):
            return "Image: \(image.sourceName) (\(image.width)x\(image.height))"
        case let .file(file):
            return "File: \(file.name)\nPath: \(file.url.path)"
        case let .url(url):
            return "URL: \(url.absoluteString)"
        case let .audio(audio):
            if let duration = audio.duration {
                return "Audio: \(audio.name)\nDuration: \(duration) seconds"
            }
            return "Audio: \(audio.name)"
        }
    }

    var searchText: String {
        switch self {
        case let .text(string):
            return string
        case let .image(image):
            return image.sourceName
        case let .file(file):
            return "\(file.name) \(file.url.path)"
        case let .url(url):
            return url.absoluteString
        case let .audio(audio):
            return audio.name
        }
    }

    var persistenceHash: String {
        let value: String
        switch self {
        case let .text(string):
            value = "text\u{0}\(string)"
        case let .image(image):
            if let contentHash = image.contentHash {
                return contentHash
            }
            value = "image\u{0}\(image.sourceName)\u{0}\(image.width)x\(image.height)\u{0}\(image.originalPath ?? image.thumbnailPath)"
        case let .file(file):
            value = "file\u{0}\(file.url.standardizedFileURL.path)"
        case let .url(url):
            value = "url\u{0}\(url.absoluteString)"
        case let .audio(audio):
            value = "audio\u{0}\(audio.cachePath)"
        }
        return Self.sha256(value.data(using: .utf8) ?? Data())
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ImageClipboardContent: Hashable, Sendable {
    let thumbnailPath: String // Path to thumbnail on disk
    let originalPath: String? // Path to original image on disk (nil if too large)
    let sourceName: String // Original file name or "Screenshot" for captures
    let width: Int
    let height: Int
    let previewText: String
    let ownsCachedFiles: Bool
    let contentHash: String?

    init(
        thumbnailPath: String,
        originalPath: String?,
        sourceName: String,
        width: Int,
        height: Int,
        ownsCachedFiles: Bool = true,
        contentHash: String? = nil
    ) {
        self.thumbnailPath = thumbnailPath
        self.originalPath = originalPath
        self.sourceName = sourceName
        self.width = width
        self.height = height
        previewText = sourceName
        self.ownsCachedFiles = ownsCachedFiles
        self.contentHash = contentHash
    }
}

struct FileClipboardContent: Hashable, Sendable {
    let url: URL
    let name: String
}

struct AudioClipboardContent: Hashable, Sendable {
    let cachePath: String
    let name: String
    let duration: TimeInterval?
    let ownsCachedFile: Bool

    init(
        cachePath: String,
        name: String,
        duration: TimeInterval?,
        ownsCachedFile: Bool = true
    ) {
        self.cachePath = cachePath
        self.name = name
        self.duration = duration
        self.ownsCachedFile = ownsCachedFile
    }
}
