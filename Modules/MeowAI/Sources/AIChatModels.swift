import Foundation

public enum AIChatRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
}

public struct AIChatMessage: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let role: AIChatRole
    public var content: String
    public var imagePath: String?

    public init(id: UUID = UUID(), role: AIChatRole, content: String, imagePath: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePath = imagePath
    }
}

public struct AIChatInitialInput: Sendable {
    public let text: String
    public let imagePath: String?

    public init(text: String, imagePath: String? = nil) {
        self.text = text
        self.imagePath = imagePath
    }
}
