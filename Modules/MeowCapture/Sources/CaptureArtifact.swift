import Foundation

public enum CaptureArtifactKind: String, Codable {
    case region
    case scrolling
    case window
    case display
    case edited
}

public struct CaptureArtifact: Identifiable, Codable, Equatable {
    public static let automaticOCRPixelLimit: Int64 = 20_000_000
    public static let fullResolutionEditingPixelLimit: Int64 = 40_000_000

    public let id: UUID
    public let kind: CaptureArtifactKind
    public let createdAt: Date
    public let imageURL: URL
    public let thumbnailURL: URL
    public let width: Int
    public let height: Int
    public var ocrText: String?

    public var pixelCount: Int64 {
        guard width > 0, height > 0 else { return 0 }
        let result = Int64(width).multipliedReportingOverflow(by: Int64(height))
        return result.overflow ? .max : result.partialValue
    }

    public var supportsAutomaticOCR: Bool {
        pixelCount <= Self.automaticOCRPixelLimit
    }

    public var supportsFullResolutionEditing: Bool {
        pixelCount <= Self.fullResolutionEditingPixelLimit
    }

    public init(
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

    public init(from decoder: Decoder) throws {
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
