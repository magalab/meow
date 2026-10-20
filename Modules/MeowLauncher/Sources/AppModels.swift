import Foundation

public struct AppEntry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bundleId: String?
    public let url: URL

    public init(id: String, name: String, bundleId: String?, url: URL) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.url = url
    }
}

public struct CommandEntry: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let keywords: [String]

    public init(id: String, title: String, subtitle: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
    }
}
