import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum RecordingVideoFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov

    var id: String { rawValue }
    var fileExtension: String { rawValue }
}

enum RecordingVideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc
    case hevcWithAlpha

    var id: String { rawValue }
}

enum RecordingAudioMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case system
    case microphone
    case systemAndMicrophone

    var id: String { rawValue }

    var capturesSystemAudio: Bool {
        self == .system || self == .systemAndMicrophone
    }

    var capturesMicrophone: Bool {
        self == .microphone || self == .systemAndMicrophone
    }
}

enum RecordingAudioFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac
    case alac
    case flac
    case opus

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .aac, .alac: return "m4a"
        case .flac, .opus: return "caf"
        }
    }
}

enum RecordingQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case balanced
    case high

    var id: String { rawValue }

    var bitrateMultiplier: Double {
        switch self {
        case .compact: return 0.08
        case .balanced: return 0.14
        case .high: return 0.22
        }
    }
}

enum RecordingBackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case desktop
    case transparent
    case solidColor

    var id: String { rawValue }
}

struct RecordingSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var videoFormat: RecordingVideoFormat
    var videoCodec: RecordingVideoCodec
    var quality: RecordingQuality
    var frameRate: Int
    var captureRetinaResolution: Bool
    var audioMode: RecordingAudioMode
    var audioFormat: RecordingAudioFormat
    var microphoneDeviceID: String
    var keepAudioTracksSeparate: Bool
    var showCursor: Bool
    var highlightMouseClicks: Bool
    var includeMenuBar: Bool
    var excludeMeow: Bool
    var excludedApplicationBundleIDs: [String]
    var excludeDesktopIcons: Bool
    var excludeSystemOverlays: Bool
    var countdownSeconds: Int
    var preventSleep: Bool
    var showPreview: Bool
    var cameraOverlayEnabled: Bool
    var cameraDeviceID: String
    var recordHDR: Bool
    var backgroundStyle: RecordingBackgroundStyle
    var backgroundColorHex: String
    var saveDirectory: String
    var fileNameTemplate: String
    var historyLimit: Int
    var retentionDays: Int
    var maxStorageMB: Int
    var displayHotkeyKeyCode: UInt32
    var displayHotkeyModifiers: UInt32
    var regionHotkeyKeyCode: UInt32
    var regionHotkeyModifiers: UInt32
    var windowHotkeyKeyCode: UInt32
    var windowHotkeyModifiers: UInt32
    var pauseHotkeyKeyCode: UInt32
    var pauseHotkeyModifiers: UInt32
    var stopHotkeyKeyCode: UInt32
    var stopHotkeyModifiers: UInt32
    var frameHotkeyKeyCode: UInt32
    var frameHotkeyModifiers: UInt32
    var magnifierHotkeyKeyCode: UInt32
    var magnifierHotkeyModifiers: UInt32

    init(
        enabled: Bool,
        videoFormat: RecordingVideoFormat,
        videoCodec: RecordingVideoCodec,
        quality: RecordingQuality,
        frameRate: Int,
        captureRetinaResolution: Bool,
        audioMode: RecordingAudioMode,
        audioFormat: RecordingAudioFormat,
        microphoneDeviceID: String,
        keepAudioTracksSeparate: Bool,
        showCursor: Bool,
        highlightMouseClicks: Bool,
        includeMenuBar: Bool,
        excludeMeow: Bool,
        excludedApplicationBundleIDs: [String],
        excludeDesktopIcons: Bool,
        excludeSystemOverlays: Bool,
        countdownSeconds: Int,
        preventSleep: Bool,
        showPreview: Bool,
        cameraOverlayEnabled: Bool,
        cameraDeviceID: String,
        recordHDR: Bool,
        backgroundStyle: RecordingBackgroundStyle,
        backgroundColorHex: String,
        saveDirectory: String,
        fileNameTemplate: String,
        historyLimit: Int,
        retentionDays: Int,
        maxStorageMB: Int,
        displayHotkeyKeyCode: UInt32,
        displayHotkeyModifiers: UInt32,
        regionHotkeyKeyCode: UInt32,
        regionHotkeyModifiers: UInt32,
        windowHotkeyKeyCode: UInt32,
        windowHotkeyModifiers: UInt32,
        pauseHotkeyKeyCode: UInt32,
        pauseHotkeyModifiers: UInt32,
        stopHotkeyKeyCode: UInt32,
        stopHotkeyModifiers: UInt32,
        frameHotkeyKeyCode: UInt32,
        frameHotkeyModifiers: UInt32,
        magnifierHotkeyKeyCode: UInt32,
        magnifierHotkeyModifiers: UInt32
    ) {
        self.enabled = enabled
        self.videoFormat = videoFormat
        self.videoCodec = videoCodec
        self.quality = quality
        self.frameRate = frameRate
        self.captureRetinaResolution = captureRetinaResolution
        self.audioMode = audioMode
        self.audioFormat = audioFormat
        self.microphoneDeviceID = microphoneDeviceID
        self.keepAudioTracksSeparate = keepAudioTracksSeparate
        self.showCursor = showCursor
        self.highlightMouseClicks = highlightMouseClicks
        self.includeMenuBar = includeMenuBar
        self.excludeMeow = excludeMeow
        self.excludedApplicationBundleIDs = excludedApplicationBundleIDs
        self.excludeDesktopIcons = excludeDesktopIcons
        self.excludeSystemOverlays = excludeSystemOverlays
        self.countdownSeconds = countdownSeconds
        self.preventSleep = preventSleep
        self.showPreview = showPreview
        self.cameraOverlayEnabled = cameraOverlayEnabled
        self.cameraDeviceID = cameraDeviceID
        self.recordHDR = recordHDR
        self.backgroundStyle = backgroundStyle
        self.backgroundColorHex = backgroundColorHex
        self.saveDirectory = saveDirectory
        self.fileNameTemplate = fileNameTemplate
        self.historyLimit = historyLimit
        self.retentionDays = retentionDays
        self.maxStorageMB = maxStorageMB
        self.displayHotkeyKeyCode = displayHotkeyKeyCode
        self.displayHotkeyModifiers = displayHotkeyModifiers
        self.regionHotkeyKeyCode = regionHotkeyKeyCode
        self.regionHotkeyModifiers = regionHotkeyModifiers
        self.windowHotkeyKeyCode = windowHotkeyKeyCode
        self.windowHotkeyModifiers = windowHotkeyModifiers
        self.pauseHotkeyKeyCode = pauseHotkeyKeyCode
        self.pauseHotkeyModifiers = pauseHotkeyModifiers
        self.stopHotkeyKeyCode = stopHotkeyKeyCode
        self.stopHotkeyModifiers = stopHotkeyModifiers
        self.frameHotkeyKeyCode = frameHotkeyKeyCode
        self.frameHotkeyModifiers = frameHotkeyModifiers
        self.magnifierHotkeyKeyCode = magnifierHotkeyKeyCode
        self.magnifierHotkeyModifiers = magnifierHotkeyModifiers
    }

    static let `default` = RecordingSettings(
        enabled: false,
        videoFormat: .mp4,
        videoCodec: .h264,
        quality: .high,
        frameRate: 60,
        captureRetinaResolution: true,
        audioMode: .system,
        audioFormat: .aac,
        microphoneDeviceID: "",
        keepAudioTracksSeparate: true,
        showCursor: true,
        highlightMouseClicks: false,
        includeMenuBar: true,
        excludeMeow: true,
        excludedApplicationBundleIDs: [],
        excludeDesktopIcons: false,
        excludeSystemOverlays: false,
        countdownSeconds: 3,
        preventSleep: true,
        showPreview: true,
        cameraOverlayEnabled: false,
        cameraDeviceID: "",
        recordHDR: false,
        backgroundStyle: .desktop,
        backgroundColorHex: "#1C1C1E",
        saveDirectory: "",
        fileNameTemplate: "Meow Recording yyyy-MM-dd HH.mm.ss",
        historyLimit: 100,
        retentionDays: 0,
        maxStorageMB: 0,
        displayHotkeyKeyCode: 22,
        displayHotkeyModifiers: 2560,
        regionHotkeyKeyCode: 26,
        regionHotkeyModifiers: 2560,
        windowHotkeyKeyCode: 28,
        windowHotkeyModifiers: 2560,
        pauseHotkeyKeyCode: 35,
        pauseHotkeyModifiers: 2560,
        stopHotkeyKeyCode: 1,
        stopHotkeyModifiers: 2560,
        frameHotkeyKeyCode: 8,
        frameHotkeyModifiers: 2560,
        magnifierHotkeyKeyCode: 46,
        magnifierHotkeyModifiers: 2560
    )

    private enum CodingKeys: String, CodingKey {
        case enabled, videoFormat, videoCodec, quality, frameRate, captureRetinaResolution
        case audioMode, audioFormat, microphoneDeviceID, keepAudioTracksSeparate, showCursor, highlightMouseClicks
        case includeMenuBar
        case excludeMeow, excludedApplicationBundleIDs, excludeDesktopIcons, excludeSystemOverlays
        case countdownSeconds, preventSleep, showPreview, cameraOverlayEnabled
        case cameraDeviceID, recordHDR, backgroundStyle, backgroundColorHex, saveDirectory
        case fileNameTemplate, historyLimit, retentionDays, maxStorageMB
        case displayHotkeyKeyCode, displayHotkeyModifiers, regionHotkeyKeyCode, regionHotkeyModifiers
        case windowHotkeyKeyCode, windowHotkeyModifiers, pauseHotkeyKeyCode, pauseHotkeyModifiers
        case stopHotkeyKeyCode, stopHotkeyModifiers
        case frameHotkeyKeyCode, frameHotkeyModifiers
        case magnifierHotkeyKeyCode, magnifierHotkeyModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        videoFormat = try container.decodeIfPresent(RecordingVideoFormat.self, forKey: .videoFormat) ?? defaults.videoFormat
        videoCodec = try container.decodeIfPresent(RecordingVideoCodec.self, forKey: .videoCodec) ?? defaults.videoCodec
        quality = try container.decodeIfPresent(RecordingQuality.self, forKey: .quality) ?? defaults.quality
        frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? defaults.frameRate
        captureRetinaResolution = try container.decodeIfPresent(Bool.self, forKey: .captureRetinaResolution) ?? defaults.captureRetinaResolution
        audioMode = try container.decodeIfPresent(RecordingAudioMode.self, forKey: .audioMode) ?? defaults.audioMode
        audioFormat = try container.decodeIfPresent(RecordingAudioFormat.self, forKey: .audioFormat) ?? defaults.audioFormat
        microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID) ?? defaults.microphoneDeviceID
        keepAudioTracksSeparate = try container.decodeIfPresent(Bool.self, forKey: .keepAudioTracksSeparate) ?? defaults.keepAudioTracksSeparate
        showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor) ?? defaults.showCursor
        highlightMouseClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightMouseClicks) ?? defaults.highlightMouseClicks
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar) ?? defaults.includeMenuBar
        excludeMeow = try container.decodeIfPresent(Bool.self, forKey: .excludeMeow) ?? defaults.excludeMeow
        excludedApplicationBundleIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedApplicationBundleIDs
        ) ?? defaults.excludedApplicationBundleIDs
        excludeDesktopIcons = try container.decodeIfPresent(
            Bool.self,
            forKey: .excludeDesktopIcons
        ) ?? defaults.excludeDesktopIcons
        excludeSystemOverlays = try container.decodeIfPresent(
            Bool.self,
            forKey: .excludeSystemOverlays
        ) ?? defaults.excludeSystemOverlays
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? defaults.countdownSeconds
        preventSleep = try container.decodeIfPresent(Bool.self, forKey: .preventSleep) ?? defaults.preventSleep
        showPreview = try container.decodeIfPresent(Bool.self, forKey: .showPreview) ?? defaults.showPreview
        cameraOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .cameraOverlayEnabled) ?? defaults.cameraOverlayEnabled
        cameraDeviceID = try container.decodeIfPresent(String.self, forKey: .cameraDeviceID) ?? defaults.cameraDeviceID
        recordHDR = try container.decodeIfPresent(Bool.self, forKey: .recordHDR) ?? defaults.recordHDR
        backgroundStyle = try container.decodeIfPresent(
            RecordingBackgroundStyle.self,
            forKey: .backgroundStyle
        ) ?? defaults.backgroundStyle
        backgroundColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .backgroundColorHex
        ) ?? defaults.backgroundColorHex
        saveDirectory = try container.decodeIfPresent(String.self, forKey: .saveDirectory) ?? defaults.saveDirectory
        fileNameTemplate = try container.decodeIfPresent(String.self, forKey: .fileNameTemplate) ?? defaults.fileNameTemplate
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? defaults.historyLimit
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? defaults.retentionDays
        maxStorageMB = try container.decodeIfPresent(Int.self, forKey: .maxStorageMB) ?? defaults.maxStorageMB
        displayHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .displayHotkeyKeyCode) ?? defaults.displayHotkeyKeyCode
        displayHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .displayHotkeyModifiers) ?? defaults.displayHotkeyModifiers
        regionHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .regionHotkeyKeyCode) ?? defaults.regionHotkeyKeyCode
        regionHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .regionHotkeyModifiers) ?? defaults.regionHotkeyModifiers
        windowHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .windowHotkeyKeyCode) ?? defaults.windowHotkeyKeyCode
        windowHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .windowHotkeyModifiers) ?? defaults.windowHotkeyModifiers
        pauseHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .pauseHotkeyKeyCode) ?? defaults.pauseHotkeyKeyCode
        pauseHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .pauseHotkeyModifiers) ?? defaults.pauseHotkeyModifiers
        stopHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .stopHotkeyKeyCode) ?? defaults.stopHotkeyKeyCode
        stopHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .stopHotkeyModifiers) ?? defaults.stopHotkeyModifiers
        frameHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .frameHotkeyKeyCode) ?? defaults.frameHotkeyKeyCode
        frameHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .frameHotkeyModifiers) ?? defaults.frameHotkeyModifiers
        magnifierHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .magnifierHotkeyKeyCode) ?? defaults.magnifierHotkeyKeyCode
        magnifierHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .magnifierHotkeyModifiers) ?? defaults.magnifierHotkeyModifiers
    }

    func normalized(for source: RecordingSourceKind? = nil) -> RecordingSettings {
        var value = self
        value.frameRate = min(120, max(1, frameRate))
        value.countdownSeconds = max(0, countdownSeconds)
        value.historyLimit = max(0, historyLimit)
        value.retentionDays = max(0, retentionDays)
        value.maxStorageMB = max(0, maxStorageMB)
        value.excludedApplicationBundleIDs = Array(Set(
            excludedApplicationBundleIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )).sorted()

        if value.videoCodec == .hevcWithAlpha {
            value.videoFormat = .mov
            value.recordHDR = false
        } else if value.backgroundStyle == .transparent {
            value.videoCodec = .hevcWithAlpha
            value.videoFormat = .mov
            value.recordHDR = false
        } else if value.recordHDR {
            value.videoCodec = .hevc
            value.videoFormat = .mov
        }

        if value.audioMode == .systemAndMicrophone {
            value.videoFormat = .mov
        }

        if source == .mobileDevice {
            value.videoFormat = .mov
            value.videoCodec = .h264
            value.recordHDR = false
            value.audioMode = .none
            value.backgroundStyle = .desktop
        }
        return value
    }
}

enum RecordingSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case display
    case region
    case window
    case application
    case systemAudio
    case mobileDevice

    var id: String { rawValue }
}

enum RecordingSource {
    case display(SCDisplay)
    case region(display: SCDisplay, rectInDisplayPoints: CGRect, scale: CGFloat)
    case window(SCWindow)
    case application(SCRunningApplication, display: SCDisplay)
    case contentFilter(SCContentFilter)
    case systemAudio(SCDisplay)
    case mobileDevice(String)

    var kind: RecordingSourceKind {
        switch self {
        case .display: return .display
        case .region: return .region
        case .window: return .window
        case .application: return .application
        case .contentFilter: return .window
        case .systemAudio: return .systemAudio
        case .mobileDevice: return .mobileDevice
        }
    }
}

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case countdown(Int)
    case recording(startedAt: Date)
    case paused(elapsed: TimeInterval)
    case finishing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .failed, .finishing: return false
        default: return true
        }
    }
}

struct RecordingArtifact: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: RecordingSourceKind
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL
    let thumbnailURL: URL?
    let width: Int
    let height: Int
    let fileSize: Int64
    let videoCodec: RecordingVideoCodec?
    let hasSystemAudio: Bool
    let hasMicrophoneAudio: Bool
}

struct RecordingCapabilities: Equatable, Sendable {
    let supportsHEVC: Bool
    let supportsHEVCWithAlpha: Bool
    let supportsHDR: Bool
    let supportsPresenterOverlay: Bool
    let hasCamera: Bool
    let hasMicrophone: Bool
    let hasMobileCaptureDevice: Bool
}

enum RecordingCommand: Equatable {
    case recordDisplay
    case recordRegion
    case recordWindow
    case recordWindows
    case recordApplication
    case recordSystemAudio
    case recordMobileDevice
    case pauseResume
    case stop
    case saveCurrentFrame
    case toggleMagnifier
    case openHistory
}
