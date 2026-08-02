import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WhiteboardDocumentStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case loadFailedRecovered(originalDescription: String, recoveryURL: URL)
    case recoveryFailed(originalDescription: String, backupDescription: String)
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return String(
                format: String(localized: "whiteboard.error.schema.unsupported", bundle: .module),
                version
            )
        case let .loadFailedRecovered(originalDescription, recoveryURL):
            return String(
                format: String(localized: "whiteboard.error.workspace.recovered", bundle: .module),
                originalDescription,
                recoveryURL.path
            )
        case let .recoveryFailed(originalDescription, backupDescription):
            return String(
                format: String(localized: "whiteboard.error.workspace.recovery.failed", bundle: .module),
                originalDescription,
                backupDescription
            )
        case .imageTooLarge:
            return String(localized: "whiteboard.error.image.too.large", bundle: .module)
        }
    }
}

struct WhiteboardDocumentStore {
    let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    var documentURL: URL {
        directory.appendingPathComponent("workspace.json", isDirectory: false)
    }

    var imagesDirectory: URL {
        directory.appendingPathComponent("Images", isDirectory: true)
    }

    var recoveryDirectory: URL {
        directory.appendingPathComponent("Recovery", isDirectory: true)
    }

    func load() throws -> WhiteboardDocument {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            return .empty()
        }

        do {
            let data = try Data(contentsOf: documentURL)
            let document = try Self.decoder.decode(WhiteboardDocument.self, from: data)
            guard document.schemaVersion <= WhiteboardDocument.currentSchemaVersion else {
                throw WhiteboardDocumentStoreError.unsupportedSchema(document.schemaVersion)
            }
            let normalized = document.normalized()
            guard Self.hasUniqueIdentifiers(in: normalized) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return normalized
        } catch let loadError {
            let recoveryURL: URL
            do {
                recoveryURL = try backupCurrentWorkspace(reason: "load-failed")
            } catch let backupError {
                throw WhiteboardDocumentStoreError.recoveryFailed(
                    originalDescription: loadError.localizedDescription,
                    backupDescription: backupError.localizedDescription
                )
            }
            throw WhiteboardDocumentStoreError.loadFailedRecovered(
                originalDescription: loadError.localizedDescription,
                recoveryURL: recoveryURL
            )
        }
    }

    func save(
        _ document: WhiteboardDocument,
        preservingImageResourceIDs: Set<UUID> = []
    ) throws {
        guard Self.hasUniqueIdentifiers(in: document) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try createDirectories()
        let data = try Self.encoder.encode(document.normalized())
        try data.write(to: documentURL, options: .atomic)
        try removeOrphanedImageFiles(
            referencedBy: document,
            preservingImageResourceIDs: preservingImageResourceIDs
        )
    }

    func createDirectories() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
    }

    func saveImage(_ image: CGImage, id: UUID) throws -> URL {
        guard Self.isSupportedImageSize(width: image.width, height: image.height) else {
            throw WhiteboardDocumentStoreError.imageTooLarge
        }
        try createDirectories()
        let url = imagesDirectory
            .appendingPathComponent(id.uuidString.lowercased())
            .appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    func savePNGData(_ data: Data, id: UUID) throws -> URL {
        try createDirectories()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard Self.isSupportedImageSize(width: width, height: height) else {
            throw WhiteboardDocumentStoreError.imageTooLarge
        }
        guard
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let url = imagesDirectory
            .appendingPathComponent(id.uuidString.lowercased())
            .appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    func imageData(for resource: WhiteboardImageResource) -> Data? {
        try? Data(contentsOf: imageURL(for: resource))
    }

    func imageURL(for resource: WhiteboardImageResource) -> URL {
        let candidate = directory
            .appendingPathComponent(resource.relativePath)
            .standardizedFileURL
        let root = directory.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(root) else {
            return imagesDirectory
                .appendingPathComponent(resource.id.uuidString.lowercased())
                .appendingPathExtension("png")
        }
        return candidate
    }

    @discardableResult
    func backupCurrentWorkspace(reason: String) throws -> URL {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try createDirectories()
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safeReason = reason.replacingOccurrences(
            of: "[^A-Za-z0-9-]",
            with: "-",
            options: .regularExpression
        )
        let backupDirectory = recoveryDirectory.appendingPathComponent(
            "\(safeReason)-\(timestamp)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: documentURL,
            to: backupDirectory.appendingPathComponent("workspace.json")
        )
        let imageFiles = try fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if !imageFiles.isEmpty {
            let backupImages = backupDirectory.appendingPathComponent("Images", isDirectory: true)
            try fileManager.createDirectory(at: backupImages, withIntermediateDirectories: true)
            for imageFile in imageFiles {
                try fileManager.copyItem(
                    at: imageFile,
                    to: backupImages.appendingPathComponent(imageFile.lastPathComponent)
                )
            }
        }
        return backupDirectory
    }

    private func removeOrphanedImageFiles(
        referencedBy document: WhiteboardDocument,
        preservingImageResourceIDs: Set<UUID>
    ) throws {
        var referencedNames = Set(document.imageResources.map {
            imageURL(for: $0).lastPathComponent
        })
        referencedNames.formUnion(preservingImageResourceIDs.map {
            $0.uuidString.lowercased() + ".png"
        })
        let files = try fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for file in files {
            guard file.pathExtension.lowercased() == "png",
                  UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  !referencedNames.contains(file.lastPathComponent)
            else { continue }
            try fileManager.removeItem(at: file)
        }
    }

    private static func isSupportedImageSize(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= 32_768, height <= 32_768 else { return false }
        return Double(width) * Double(height) <= 100_000_000
    }

    private static func hasUniqueIdentifiers(in document: WhiteboardDocument) -> Bool {
        let elementExternalIDs = document.elements.compactMap(\.externalID)
        let imageExternalIDs = document.imageResources.compactMap(\.externalID)
        return Set(document.elements.map(\.id)).count == document.elements.count
            && Set(document.imageResources.map(\.id)).count == document.imageResources.count
            && Set(elementExternalIDs).count == elementExternalIDs.count
            && Set(imageExternalIDs).count == imageExternalIDs.count
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
