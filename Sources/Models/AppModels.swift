import Foundation

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleId: String?
    let url: URL
}

struct CommandEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
}
