import CoreGraphics
import Foundation

public enum WhiteboardIdleVisibility: String, Codable, Sendable {
    case hidden
    case visible
}

public enum WhiteboardSurfaceStyle: String, Codable, Sendable, CaseIterable {
    case transparent
    case paper
}

public enum WhiteboardGuideStyle: String, Codable, Sendable, CaseIterable {
    case none
    case dots
    case grid
}

public enum WhiteboardOutputBackgroundStyle: String, Codable, Sendable, CaseIterable {
    case transparent
    case paper
}

public enum WhiteboardCapturePolicy: String, Codable, Sendable {
    case includeContent
    case excludeContent
}

public enum WhiteboardExportFormat: String, Sendable {
    case png
    case svg
    case excalidraw
}

public struct WhiteboardConfiguration: Equatable, Sendable {
    public var isEnabled: Bool
    public var idleVisibility: WhiteboardIdleVisibility
    public var includeInCaptures: Bool
    public var surfaceStyle: WhiteboardSurfaceStyle
    public var guideStyle: WhiteboardGuideStyle
    public var outputBackgroundStyle: WhiteboardOutputBackgroundStyle
    public var editOpacity: Double
    public var storageDirectory: URL
    public var languageCode: String?
    public var applicationName: String

    public init(
        isEnabled: Bool,
        idleVisibility: WhiteboardIdleVisibility = .hidden,
        includeInCaptures: Bool = true,
        surfaceStyle: WhiteboardSurfaceStyle = .paper,
        guideStyle: WhiteboardGuideStyle = .dots,
        outputBackgroundStyle: WhiteboardOutputBackgroundStyle = .transparent,
        editOpacity: Double = 0.94,
        storageDirectory: URL,
        languageCode: String? = nil,
        applicationName: String = "Meow"
    ) {
        self.isEnabled = isEnabled
        self.idleVisibility = idleVisibility
        self.includeInCaptures = includeInCaptures
        self.surfaceStyle = surfaceStyle
        self.guideStyle = guideStyle
        self.outputBackgroundStyle = outputBackgroundStyle
        self.editOpacity = editOpacity.isFinite
            ? min(1, max(0.2, editOpacity))
            : 0.94
        self.storageDirectory = storageDirectory
        self.languageCode = languageCode
        self.applicationName = applicationName
    }
}

public enum WhiteboardFeatureState: Equatable, Sendable {
    case disabled
    case idle
    case editing
}

public struct WhiteboardImportedImage: Sendable {
    public let image: CGImage
    public let sourceName: String?

    public init(image: CGImage, sourceName: String? = nil) {
        self.image = image
        self.sourceName = sourceName
    }
}
