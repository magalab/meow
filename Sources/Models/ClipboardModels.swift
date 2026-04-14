import Foundation

struct ClipboardEntry: Identifiable, Hashable {
    let id: String
    let content: ClipboardContent
    let copiedAt: Date

    var preview: String {
        content.preview
    }

    var symbolName: String {
        content.symbolName
    }
}

enum ClipboardContent: Hashable {
    case text(String)
    case image(ImageClipboardContent)
    case file(FileClipboardContent)
    case url(URL)
    case audio(AudioClipboardContent)

    var preview: String {
        switch self {
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count <= 50 {
                return singleLine
            }
            let index = singleLine.index(singleLine.startIndex, offsetBy: 50)
            return String(singleLine[..<index]) + "…"
        case .image(let image):
            return image.previewText
        case .file(let file):
            return file.url.lastPathComponent
        case .url(let url):
            return url.absoluteString
        case .audio(let audio):
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

    var typeLabel: String {
        switch self {
        case .text:
            return L10n.clipboardTypeText
        case .image:
            return L10n.clipboardTypeImage
        case .file:
            return L10n.clipboardTypeFile
        case .url:
            return L10n.clipboardTypeURL
        case .audio:
            return L10n.clipboardTypeAudio
        }
    }
}

struct ImageClipboardContent: Hashable {
    let thumbnailPath: String  // Path to thumbnail on disk
    let originalPath: String?  // Path to original image on disk (nil if too large)
    let sourceName: String  // Original file name or "Screenshot" for captures
    let width: Int
    let height: Int
    let previewText: String

    init(thumbnailPath: String, originalPath: String?, sourceName: String, width: Int, height: Int) {
        self.thumbnailPath = thumbnailPath
        self.originalPath = originalPath
        self.sourceName = sourceName
        self.width = width
        self.height = height
        self.previewText = sourceName
    }
}

struct FileClipboardContent: Hashable {
    let url: URL
    let name: String
}

struct AudioClipboardContent: Hashable {
    let cachePath: String
    let name: String
    let duration: TimeInterval?
}

enum SearchItem: Identifiable, Hashable {
    case app(AppEntry)
    case command(CommandEntry)
    case clipboard(ClipboardEntry)

    var id: String {
        switch self {
        case .app(let app):
            return "app:\(app.id)"
        case .command(let command):
            return "command:\(command.id)"
        case .clipboard(let entry):
            return "clipboard:\(entry.id)"
        }
    }

    var primaryText: String {
        switch self {
        case .app(let app):
            return app.name
        case .command(let command):
            return command.title
        case .clipboard(let entry):
            return entry.preview
        }
    }

    var secondaryText: String {
        switch self {
        case .app:
            return L10n.categoryApplication
        case .command(let command):
            return command.subtitle
        case .clipboard(let entry):
            return entry.content.typeLabel
        }
    }

    var symbolName: String {
        switch self {
        case .app:
            return "app.fill"
        case .command(let command):
            if command.id == "meow.preferences" {
                return "slider.horizontal.3"
            }
            if command.id == "meow.quit" {
                return "power"
            }
            return "command"
        case .clipboard(let entry):
            return entry.symbolName
        }
    }
}
