import Foundation
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard document storage")
struct WhiteboardDocumentStoreTests {
    @Test("Document round trips through the canonical workspace file")
    func documentRoundTrip() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let element = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 20, y: 30),
            size: WhiteboardSize(width: 120, height: 80),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        var document = WhiteboardDocument.empty()
        document.elements = [element]

        try store.save(document)
        let loaded = try store.load()

        #expect(loaded.elements == [element])
        #expect(loaded.schemaVersion == WhiteboardDocument.currentSchemaVersion)
    }

    @Test("Missing workspace loads without creating storage")
    func missingWorkspaceDoesNotCreateStorage() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)

        let loaded = try store.load()

        #expect(loaded.elements.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Corrupt workspace and images are preserved before returning a recovery error")
    func corruptWorkspaceIsPreserved() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        try store.createDirectories()
        let corruptData = Data("not-json".utf8)
        let imageName = "\(UUID().uuidString.lowercased()).png"
        try corruptData.write(to: store.documentURL)
        try Data([1, 2, 3]).write(to: store.imagesDirectory.appendingPathComponent(imageName))

        #expect(throws: WhiteboardDocumentStoreError.self) {
            try store.load()
        }

        let snapshots = try FileManager.default.contentsOfDirectory(
            at: store.recoveryDirectory,
            includingPropertiesForKeys: nil
        )
        let snapshot = try #require(snapshots.first)
        #expect(snapshots.count == 1)
        #expect(
            try Data(contentsOf: snapshot.appendingPathComponent("workspace.json"))
                == corruptData
        )
        #expect(
            try Data(contentsOf: snapshot.appendingPathComponent("Images/\(imageName)"))
                == Data([1, 2, 3])
        )
    }

    @Test("Load does not report recovery when the recovery snapshot cannot be created")
    func failedRecoveryIsReported() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.documentURL)
        try Data("blocks-directory-creation".utf8).write(to: store.recoveryDirectory)

        do {
            _ = try store.load()
            Issue.record("Expected workspace loading to fail")
        } catch let error as WhiteboardDocumentStoreError {
            guard case .recoveryFailed = error else {
                Issue.record("Expected recoveryFailed, received \(error)")
                return
            }
        }
    }

    @Test("A native workspace with duplicate identifiers is recovered instead of loaded")
    func duplicateNativeIdentifiersAreRecovered() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        let id = UUID()
        var document = WhiteboardDocument.empty()
        document.elements = [
            WhiteboardElement(
                id: id,
                kind: .rectangle,
                origin: WhiteboardPoint(x: 0, y: 0),
                size: WhiteboardSize(width: 10, height: 10)
            ),
            WhiteboardElement(
                id: id,
                kind: .ellipse,
                origin: WhiteboardPoint(x: 20, y: 20),
                size: WhiteboardSize(width: 10, height: 10)
            ),
        ]
        try store.createDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(document).write(to: store.documentURL)

        do {
            _ = try store.load()
            Issue.record("Expected duplicate identifiers to be rejected")
        } catch let error as WhiteboardDocumentStoreError {
            guard case .loadFailedRecovered = error else {
                Issue.record("Expected loadFailedRecovered, received \(error)")
                return
            }
        }
    }

    @Test("Saving removes only unreferenced UUID image files")
    func orphanImageCleanup() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        try store.createDirectories()
        let referencedID = UUID()
        let orphanID = UUID()
        let referencedURL = store.imagesDirectory
            .appendingPathComponent(referencedID.uuidString.lowercased())
            .appendingPathExtension("png")
        let orphanURL = store.imagesDirectory
            .appendingPathComponent(orphanID.uuidString.lowercased())
            .appendingPathExtension("png")
        let unrelatedURL = store.imagesDirectory.appendingPathComponent("keep-me.txt")
        try Data([1]).write(to: referencedURL)
        try Data([2]).write(to: orphanURL)
        try Data([3]).write(to: unrelatedURL)
        var document = WhiteboardDocument.empty()
        document.imageResources = [WhiteboardImageResource(
            id: referencedID,
            relativePath: "Images/\(referencedURL.lastPathComponent)",
            sourceName: nil,
            pixelWidth: 1,
            pixelHeight: 1
        )]

        try store.save(document)

        #expect(FileManager.default.fileExists(atPath: referencedURL.path))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test("Documents written before bindings were added still decode")
    func missingOptionalBindingsDecode() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let documentID = UUID()
        let elementID = UUID()
        let source = """
        {
          "schemaVersion": 1,
          "id": "\(documentID.uuidString)",
          "elements": [{
            "id": "\(elementID.uuidString)",
            "kind": "rectangle",
            "origin": {"x": 0, "y": 0},
            "size": {"width": 10, "height": 10},
            "rotation": 0,
            "points": [],
            "style": {"strokeHex": "#000000", "lineWidth": 2, "opacity": 1, "fontSize": 20},
            "createdAt": \(timestamp.timeIntervalSince1970),
            "updatedAt": \(timestamp.timeIntervalSince1970)
          }],
          "camera": {"offset": {"x": 0, "y": 0}, "zoom": 1},
          "imageResources": [],
          "createdAt": \(timestamp.timeIntervalSince1970),
          "modifiedAt": \(timestamp.timeIntervalSince1970)
        }
        """
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WhiteboardDocumentStore(directory: directory)
        try Data(source.utf8).write(to: store.documentURL)

        let loaded = try store.load()

        #expect(loaded.elements.count == 1)
        #expect(loaded.elements[0].startBinding == nil)
        #expect(loaded.elements[0].endBinding == nil)
    }

    @Test("Pre-import recovery snapshot contains workspace and images")
    func recoverySnapshotContainsResources() throws {
        let directory = temporaryDirectory()
        let store = WhiteboardDocumentStore(directory: directory)
        let resourceID = UUID()
        let fileName = "\(resourceID.uuidString.lowercased()).png"
        var document = WhiteboardDocument.empty()
        document.imageResources = [WhiteboardImageResource(
            id: resourceID,
            relativePath: "Images/\(fileName)",
            sourceName: "sample.png",
            pixelWidth: 1,
            pixelHeight: 1
        )]
        try store.createDirectories()
        try Data([1, 2, 3]).write(to: store.imagesDirectory.appendingPathComponent(fileName))
        try store.save(document)

        try store.backupCurrentWorkspace(reason: "before-import")

        let snapshots = try FileManager.default.contentsOfDirectory(
            at: store.recoveryDirectory,
            includingPropertiesForKeys: nil
        )
        let snapshot = try #require(snapshots.first)
        #expect(FileManager.default.fileExists(
            atPath: snapshot.appendingPathComponent("workspace.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: snapshot.appendingPathComponent("Images/\(fileName)").path
        ))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-WhiteboardTests-\(UUID().uuidString)", isDirectory: true)
    }
}
