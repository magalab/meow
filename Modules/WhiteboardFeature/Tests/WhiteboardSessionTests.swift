import Foundation
import CoreGraphics
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard editing history")
@MainActor
struct WhiteboardSessionTests {
    @Test("Undo history remains bounded and supports one hundred reversals")
    func undoLimit() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-WhiteboardSessionTests-\(UUID().uuidString)")
        let session = WhiteboardSession(
            document: .empty(),
            store: WhiteboardDocumentStore(directory: directory)
        )

        for index in 0..<105 {
            session.add(WhiteboardElement(
                kind: .rectangle,
                origin: WhiteboardPoint(x: Double(index), y: 0),
                size: WhiteboardSize(width: 10, height: 10)
            ))
        }
        for _ in 0..<100 {
            session.undo()
        }

        #expect(session.document.elements.count == 5)
        #expect(!session.canUndo)
        #expect(session.canRedo)
    }

    @Test("Bound arrow endpoints follow moved shapes")
    func boundArrowFollowsShape() {
        let target = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 10, y: 20),
            size: WhiteboardSize(width: 100, height: 60)
        )
        let arrow = WhiteboardElement(
            kind: .arrow,
            origin: WhiteboardPoint(x: 110, y: 50),
            size: WhiteboardSize(width: 100, height: 1),
            points: [WhiteboardPoint(x: 110, y: 50), WhiteboardPoint(x: 210, y: 50)],
            startBinding: WhiteboardElementBinding(
                elementID: target.id,
                normalizedPosition: WhiteboardPoint(x: 1, y: 0.5)
            )
        )
        var document = WhiteboardDocument.empty()
        document.elements = [target, arrow]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-WhiteboardBindingTests-\(UUID().uuidString)")
        let session = WhiteboardSession(
            document: document,
            store: WhiteboardDocumentStore(directory: directory)
        )
        session.selectedElementIDs = [target.id]

        session.translateSelected(by: CGPoint(x: 25, y: -10))

        let movedArrow = session.document.elements[1]
        #expect(movedArrow.points[0] == WhiteboardPoint(x: 135, y: 40))
        #expect(movedArrow.points[1] == WhiteboardPoint(x: 210, y: 50))
    }

    @Test("Removing an image keeps undo data until the session closes")
    func imageResourceFollowsUndoLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-WhiteboardImageHistoryTests-\(UUID().uuidString)")
        let store = WhiteboardDocumentStore(directory: directory)
        let session = WhiteboardSession(document: .empty(), store: store)
        let image = try #require(makeOnePixelImage())

        try session.addImage(image, sourceName: "pixel.png", center: .zero)
        let element = try #require(session.document.elements.first)
        let resource = try #require(session.document.imageResources.first)
        let imageURL = store.imageURL(for: resource)

        session.remove(ids: [element.id])
        session.saveNow()

        #expect(session.document.imageResources.isEmpty)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))

        session.undo()
        #expect(session.document.imageResources == [resource])
        #expect(session.image(for: resource.id) != nil)

        session.redo()
        #expect(session.document.imageResources.isEmpty)
        session.close()
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test("Duplicating a bound selection remaps bindings to duplicated shapes")
    func duplicateRemapsBindings() throws {
        let shape = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 10, y: 20),
            size: WhiteboardSize(width: 100, height: 60)
        )
        let arrow = WhiteboardElement(
            kind: .arrow,
            origin: WhiteboardPoint(x: 110, y: 50),
            size: WhiteboardSize(width: 100, height: 1),
            points: [WhiteboardPoint(x: 110, y: 50), WhiteboardPoint(x: 210, y: 50)],
            startBinding: WhiteboardElementBinding(
                elementID: shape.id,
                normalizedPosition: WhiteboardPoint(x: 1, y: 0.5)
            )
        )

        let duplicated = WhiteboardElementDuplicator.duplicate(
            [shape, arrow],
            offset: CGPoint(x: 20, y: 20)
        )
        let duplicatedShape = duplicated[0]
        let duplicatedArrow = duplicated[1]

        #expect(duplicatedShape.id != shape.id)
        #expect(duplicatedArrow.id != arrow.id)
        #expect(duplicatedArrow.startBinding?.elementID == duplicatedShape.id)
        #expect(duplicatedArrow.startBinding?.elementID != shape.id)

        let arrowOnly = try #require(
            WhiteboardElementDuplicator.duplicate([arrow], offset: .zero).first
        )
        #expect(arrowOnly.startBinding == nil)
    }

    private func makeOnePixelImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }
}
