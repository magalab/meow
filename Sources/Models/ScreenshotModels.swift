import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenshotOutputMode: String, Codable, CaseIterable, Identifiable {
    case copy
    case save
    case copyAndSave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return L10n.screenshotOutputCopy
        case .save: return L10n.screenshotOutputSave
        case .copyAndSave: return L10n.screenshotOutputCopyAndSave
        }
    }
}

enum ScreenshotImageFormat: String, Codable, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }
    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
}

enum ScreenshotOCRLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var visionIdentifier: String {
        switch self {
        case .simplifiedChinese: return "zh-Hans"
        case .english: return "en-US"
        }
    }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return L10n.prefsScreenshotOCRChinese
        case .english: return L10n.prefsScreenshotOCREnglish
        }
    }
}

enum PostCaptureActionDuration: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case twentySeconds = 20

    var id: Int { rawValue }
    var seconds: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .never:
            return L10n.prefsScreenshotPostActionsNever
        case .fiveSeconds, .tenSeconds, .twentySeconds:
            return String(format: L10n.prefsScreenshotPostActionsSeconds, rawValue)
        }
    }
}

struct ScreenshotSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var defaultCaptureMode: ScreenshotCaptureMode
    var regionHotkeyKeyCode: UInt32
    var regionHotkeyModifiers: UInt32
    var editHotkeyKeyCode: UInt32
    var editHotkeyModifiers: UInt32
    var windowHotkeyKeyCode: UInt32
    var windowHotkeyModifiers: UInt32
    var displayHotkeyKeyCode: UInt32
    var displayHotkeyModifiers: UInt32
    var outputMode: ScreenshotOutputMode
    var imageFormat: ScreenshotImageFormat
    var jpegQuality: Double
    var saveDirectory: String
    var fileNameTemplate: String
    var includeWindowShadow: Bool
    var playSound: Bool
    var showPostCaptureActions: Bool
    var postCaptureActionDuration: PostCaptureActionDuration
    var historyLimit: Int
    var retentionDays: Int
    var maxStorageMB: Int
    var automaticallyIndexOCRText: Bool
    var ocrLanguages: [ScreenshotOCRLanguage]

    static let `default` = ScreenshotSettings(
        enabled: true,
        defaultCaptureMode: .region,
        regionHotkeyKeyCode: 19,
        regionHotkeyModifiers: 2560,
        editHotkeyKeyCode: 18,
        editHotkeyModifiers: 2560,
        windowHotkeyKeyCode: 20,
        windowHotkeyModifiers: 2560,
        displayHotkeyKeyCode: 21,
        displayHotkeyModifiers: 2560,
        outputMode: .copy,
        imageFormat: .png,
        jpegQuality: 0.9,
        saveDirectory: "",
        fileNameTemplate: "Meow Screenshot yyyy-MM-dd HH.mm.ss",
        includeWindowShadow: true,
        playSound: true,
        showPostCaptureActions: true,
        postCaptureActionDuration: .tenSeconds,
        historyLimit: 100,
        retentionDays: 0,
        maxStorageMB: 0,
        automaticallyIndexOCRText: false,
        ocrLanguages: [.simplifiedChinese, .english]
    )
}

extension ScreenshotSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case defaultCaptureMode
        case regionHotkeyKeyCode
        case regionHotkeyModifiers
        case editHotkeyKeyCode
        case editHotkeyModifiers
        case windowHotkeyKeyCode
        case windowHotkeyModifiers
        case displayHotkeyKeyCode
        case displayHotkeyModifiers
        case outputMode
        case imageFormat
        case jpegQuality
        case saveDirectory
        case fileNameTemplate
        case includeWindowShadow
        case playSound
        case showPostCaptureActions
        case postCaptureActionDuration
        case historyLimit
        case retentionDays
        case maxStorageMB
        case automaticallyIndexOCRText
        case ocrLanguages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        defaultCaptureMode = try container.decodeIfPresent(
            ScreenshotCaptureMode.self,
            forKey: .defaultCaptureMode
        ) ?? Self.default.defaultCaptureMode
        regionHotkeyKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .regionHotkeyKeyCode
        ) ?? Self.default.regionHotkeyKeyCode
        regionHotkeyModifiers = try container.decodeIfPresent(
            UInt32.self,
            forKey: .regionHotkeyModifiers
        ) ?? Self.default.regionHotkeyModifiers
        editHotkeyKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .editHotkeyKeyCode
        ) ?? Self.default.editHotkeyKeyCode
        editHotkeyModifiers = try container.decodeIfPresent(
            UInt32.self,
            forKey: .editHotkeyModifiers
        ) ?? Self.default.editHotkeyModifiers
        windowHotkeyKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .windowHotkeyKeyCode
        ) ?? Self.default.windowHotkeyKeyCode
        windowHotkeyModifiers = try container.decodeIfPresent(
            UInt32.self,
            forKey: .windowHotkeyModifiers
        ) ?? Self.default.windowHotkeyModifiers
        displayHotkeyKeyCode = try container.decodeIfPresent(
            UInt32.self,
            forKey: .displayHotkeyKeyCode
        ) ?? Self.default.displayHotkeyKeyCode
        displayHotkeyModifiers = try container.decodeIfPresent(
            UInt32.self,
            forKey: .displayHotkeyModifiers
        ) ?? Self.default.displayHotkeyModifiers
        outputMode = try container.decodeIfPresent(
            ScreenshotOutputMode.self,
            forKey: .outputMode
        ) ?? Self.default.outputMode
        imageFormat = try container.decodeIfPresent(
            ScreenshotImageFormat.self,
            forKey: .imageFormat
        ) ?? Self.default.imageFormat
        jpegQuality = try container.decodeIfPresent(
            Double.self,
            forKey: .jpegQuality
        ) ?? Self.default.jpegQuality
        saveDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .saveDirectory
        ) ?? Self.default.saveDirectory
        fileNameTemplate = try container.decodeIfPresent(
            String.self,
            forKey: .fileNameTemplate
        ) ?? Self.default.fileNameTemplate
        includeWindowShadow = try container.decodeIfPresent(
            Bool.self,
            forKey: .includeWindowShadow
        ) ?? Self.default.includeWindowShadow
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? Self.default.playSound
        showPostCaptureActions = try container.decodeIfPresent(
            Bool.self,
            forKey: .showPostCaptureActions
        ) ?? Self.default.showPostCaptureActions
        postCaptureActionDuration = try container.decodeIfPresent(
            PostCaptureActionDuration.self,
            forKey: .postCaptureActionDuration
        ) ?? Self.default.postCaptureActionDuration
        historyLimit = try container.decodeIfPresent(
            Int.self,
            forKey: .historyLimit
        ) ?? Self.default.historyLimit
        retentionDays = try container.decodeIfPresent(
            Int.self,
            forKey: .retentionDays
        ) ?? Self.default.retentionDays
        maxStorageMB = try container.decodeIfPresent(
            Int.self,
            forKey: .maxStorageMB
        ) ?? Self.default.maxStorageMB
        automaticallyIndexOCRText = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyIndexOCRText
        ) ?? Self.default.automaticallyIndexOCRText
        let decodedLanguages = try container.decodeIfPresent(
            [ScreenshotOCRLanguage].self,
            forKey: .ocrLanguages
        ) ?? Self.default.ocrLanguages
        ocrLanguages = decodedLanguages.isEmpty ? Self.default.ocrLanguages : decodedLanguages
    }
}

enum ScreenshotCaptureMode: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case region
    case window
    case display

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .region: return L10n.screenshotKindRegion
        case .window: return L10n.screenshotKindWindow
        case .display: return L10n.screenshotKindDisplay
        }
    }
}

enum ScreenshotCommand: Equatable {
    case captureRegion
    case captureAndEdit
    case captureWindow
    case captureDisplay
    case openHistory
}

enum CaptureSelection {
    case region(display: SCDisplay, rectInDisplayPoints: CGRect, scale: CGFloat)
    case window(SCWindow, scale: CGFloat)
    case display(SCDisplay, scale: CGFloat)
}

struct FrozenDisplay {
    let display: SCDisplay
    let screen: NSScreen
    let image: CGImage
    let scale: CGFloat
}

struct CaptureSession {
    let content: SCShareableContent
    let displays: [FrozenDisplay]
    let windows: [SCWindow]
}

enum CaptureArtifactKind: String, Codable {
    case region
    case window
    case display
    case edited
}

struct CaptureArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: CaptureArtifactKind
    let createdAt: Date
    let imageURL: URL
    let thumbnailURL: URL
    let width: Int
    let height: Int
    var ocrText: String?

    init(
        id: UUID,
        kind: CaptureArtifactKind,
        createdAt: Date,
        imageURL: URL,
        thumbnailURL: URL,
        width: Int,
        height: Int,
        ocrText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.ocrText = ocrText
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case imageURL
        case thumbnailURL
        case width
        case height
        case ocrText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(CaptureArtifactKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        thumbnailURL = try container.decode(URL.self, forKey: .thumbnailURL)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
    }
}
