import CryptoKit
import Foundation

public struct ClipboardEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let content: ClipboardContent
    public let copiedAt: Date
    public let sourceBundleID: String?
    public let pinnedAt: Date?

    public init(
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

    public var isPinned: Bool {
        pinnedAt != nil
    }

    public func with(copiedAt: Date? = nil, pinnedAt: Date?) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            copiedAt: copiedAt ?? self.copiedAt,
            sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt
        )
    }

    public var preview: String {
        content.preview
    }

    public var symbolName: String {
        content.symbolName
    }
}

public enum ClipboardContent: Hashable, Sendable {
    case text(String)
    case image(ImageClipboardContent)
    case file(FileClipboardContent)
    case url(URL)
    case audio(AudioClipboardContent)

    public var preview: String {
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

    public var symbolName: String {
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

    public var aiContextText: String {
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

    public var searchText: String {
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

    public var persistenceHash: String {
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

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ImageClipboardContent: Hashable, Sendable {
    public let thumbnailPath: String
    public let originalPath: String?
    public let sourceName: String
    public let width: Int
    public let height: Int
    public let previewText: String
    public let ownsCachedFiles: Bool
    public let contentHash: String?

    public init(
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

public struct FileClipboardContent: Hashable, Sendable {
    public let url: URL
    public let name: String

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

public struct AudioClipboardContent: Hashable, Sendable {
    public let cachePath: String
    public let name: String
    public let duration: TimeInterval?
    public let ownsCachedFile: Bool

    public init(
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
