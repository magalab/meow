import Foundation
import ImageIO
import UniformTypeIdentifiers

private actor UploadHistoryDiskStore {
    nonisolated let directoryURL: URL
    private let metadataURL: URL
    private let fileManager = FileManager.default

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        metadataURL = directoryURL.appendingPathComponent("index.json")
    }

    func load() -> [UploadHistoryEntry] {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([UploadHistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }

    func persist(_ entries: [UploadHistoryEntry]) {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    func makeThumbnail(for imageURL: URL, id: UUID) -> String? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary)
        else { return nil }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let filename = "\(id.uuidString).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.75,
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? filename : nil
    }

    func removeThumbnail(path: String) {
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(path))
    }
}

@MainActor
final class UploadHistoryStore: ObservableObject {
    @Published private(set) var entries: [UploadHistoryEntry] = []

    private let disk: UploadHistoryDiskStore
    private let loadTask: Task<[UploadHistoryEntry], Never>
    private var didLoad = false

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meow/Uploads", isDirectory: true)
        let disk = UploadHistoryDiskStore(directoryURL: base)
        self.disk = disk
        loadTask = Task { await disk.load() }
        Task { [weak self] in await self?.ensureLoaded() }
    }

    func add(_ entry: UploadHistoryEntry, limit: Int) async {
        await ensureLoaded()
        entries.insert(entry, at: 0)
        let bounded = min(max(limit, 1), 500)
        if entries.count > bounded {
            let removed = entries.dropFirst(bounded)
            for entry in removed {
                if let path = entry.thumbnailPath { await disk.removeThumbnail(path: path) }
            }
            entries = Array(entries.prefix(bounded))
        }
        await disk.persist(entries)
    }

    func remove(_ entry: UploadHistoryEntry) async {
        await ensureLoaded()
        entries.removeAll { $0.id == entry.id }
        if let path = entry.thumbnailPath { await disk.removeThumbnail(path: path) }
        await disk.persist(entries)
    }

    func removeAll() async {
        await ensureLoaded()
        for entry in entries {
            if let path = entry.thumbnailPath { await disk.removeThumbnail(path: path) }
        }
        entries.removeAll()
        await disk.persist(entries)
    }

    func thumbnailURL(for entry: UploadHistoryEntry) -> URL? {
        guard let path = entry.thumbnailPath else { return nil }
        return disk.directoryURL.appendingPathComponent(path)
    }

    func makeThumbnail(for imageURL: URL, id: UUID) async -> String? {
        await disk.makeThumbnail(for: imageURL, id: id)
    }

    func waitUntilLoaded() async {
        await ensureLoaded()
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        let loaded = await loadTask.value
        let currentIDs = Set(entries.map(\.id))
        entries.append(contentsOf: loaded.filter { !currentIDs.contains($0.id) })
        entries.sort { $0.createdAt > $1.createdAt }
        didLoad = true
    }
}
