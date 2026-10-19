import Foundation

public enum ScreenshotImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    public var id: String { rawValue }
    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
}
