import Foundation
import ImageIO
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard file formats")
struct WhiteboardFormatTests {
    @Test("Excalidraw keeps unknown root, element, and supported-element fields")
    func excalidrawPreservesUnknownFields() throws {
        let source = """
        {
          "type": "excalidraw",
          "version": 2,
          "customRoot": {"enabled": true},
          "elements": [
            {
              "id": "known-rectangle",
              "type": "rectangle",
              "x": 10,
              "y": 20,
              "width": 100,
              "height": 80,
              "strokeColor": "#123456",
              "backgroundColor": "transparent",
              "customElement": "kept"
            },
            {
              "id": "unsupported-widget",
              "type": "embeddable",
              "x": 2,
              "y": 3,
              "width": 40,
              "height": 50,
              "customPayload": {"answer": 42}
            }
          ],
          "files": {}
        }
        """

        let decoded = try WhiteboardExcalidrawCodec.decode(Data(source.utf8))
        #expect(decoded.document.elements.map(\.kind) == [.rectangle, .unknown])

        let encoded = try WhiteboardExcalidrawCodec.encode(decoded.document) { _ in nil }
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let customRoot = try #require(root["customRoot"] as? [String: Any])
        #expect(customRoot["enabled"] as? Bool == true)
        let elements = try #require(root["elements"] as? [[String: Any]])
        #expect(elements[0]["customElement"] as? String == "kept")
        let payload = try #require(elements[1]["customPayload"] as? [String: Any])
        #expect(payload["answer"] as? Int == 42)
    }

    @Test("Excalidraw line points remain stable across a round trip")
    func excalidrawLinePointsRoundTrip() throws {
        let element = WhiteboardElement(
            kind: .arrow,
            origin: WhiteboardPoint(x: 50, y: 70),
            size: WhiteboardSize(width: 120, height: 40),
            points: [WhiteboardPoint(x: 50, y: 70), WhiteboardPoint(x: 170, y: 110)]
        )
        var document = WhiteboardDocument.empty()
        document.elements = [element]

        let data = try WhiteboardExcalidrawCodec.encode(document) { _ in nil }
        let decoded = try WhiteboardExcalidrawCodec.decode(data)

        #expect(decoded.document.elements.count == 1)
        #expect(decoded.document.elements[0].points == element.points)
    }

    @Test("SVG output contains escaped text and correct content bounds")
    func svgOutput() throws {
        let element = WhiteboardElement(
            kind: .text,
            origin: WhiteboardPoint(x: 100, y: 200),
            size: WhiteboardSize(width: 160, height: 40),
            text: "Meow & Miao <3"
        )
        var document = WhiteboardDocument.empty()
        document.elements = [element]

        let data = WhiteboardExporter.svg(document: document) { _ in nil }
        let svg = try #require(String(data: data, encoding: .utf8))

        #expect(svg.contains("Meow &amp; Miao &lt;3"))
        #expect(svg.contains("viewBox=\"60.0000 160.0000 240.0000 120.0000\""))
    }

    @Test("Excalidraw preserves arrow bindings to supported shapes")
    func excalidrawBindingRoundTrip() throws {
        let shape = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 10, y: 10),
            size: WhiteboardSize(width: 80, height: 60),
            externalID: "shape-a"
        )
        let arrow = WhiteboardElement(
            kind: .arrow,
            origin: WhiteboardPoint(x: 90, y: 40),
            size: WhiteboardSize(width: 100, height: 1),
            points: [WhiteboardPoint(x: 90, y: 40), WhiteboardPoint(x: 190, y: 40)],
            externalID: "arrow-a",
            startBinding: WhiteboardElementBinding(
                elementID: shape.id,
                normalizedPosition: WhiteboardPoint(x: 1, y: 0.5)
            )
        )
        var document = WhiteboardDocument.empty()
        document.elements = [shape, arrow]

        let encoded = try WhiteboardExcalidrawCodec.encode(document) { _ in nil }
        let decoded = try WhiteboardExcalidrawCodec.decode(encoded)
        let decodedShape = decoded.document.elements[0]
        let decodedArrow = decoded.document.elements[1]

        #expect(decodedArrow.startBinding?.elementID == decodedShape.id)
        #expect(decodedArrow.startBinding?.normalizedPosition == WhiteboardPoint(x: 1, y: 0.5))
    }

    @Test("Excalidraw rejects duplicate element identifiers")
    func excalidrawRejectsDuplicateElementIDs() throws {
        let source = """
        {
          "type": "excalidraw",
          "version": 2,
          "elements": [
            {"id": "duplicate", "type": "rectangle", "x": 0, "y": 0, "width": 10, "height": 10},
            {"id": "duplicate", "type": "ellipse", "x": 20, "y": 20, "width": 10, "height": 10}
          ],
          "files": {}
        }
        """

        #expect(throws: WhiteboardExcalidrawError.duplicateElementID("duplicate")) {
            try WhiteboardExcalidrawCodec.decode(Data(source.utf8))
        }
    }

    @Test("Excalidraw export rejects duplicate internal element identifiers")
    func excalidrawExportRejectsDuplicateElementIDs() throws {
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

        #expect(throws: WhiteboardExcalidrawError.self) {
            try WhiteboardExcalidrawCodec.encode(document) { _ in nil }
        }
    }

    @Test("Excalidraw export clears stale arrow and shape bindings")
    func excalidrawClearsStaleBindings() throws {
        let staleBinding: WhiteboardJSONValue = .object([
            "elementId": .string("deleted-shape"),
            "focus": .number(0),
            "gap": .number(1),
        ])
        let staleBoundElements: WhiteboardJSONValue = .array([
            .object(["id": .string("deleted-arrow"), "type": .string("arrow")]),
        ])
        let shape = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 0, y: 0),
            size: WhiteboardSize(width: 40, height: 40),
            externalRepresentation: ["boundElements": staleBoundElements]
        )
        let arrow = WhiteboardElement(
            kind: .arrow,
            origin: WhiteboardPoint(x: 50, y: 20),
            size: WhiteboardSize(width: 60, height: 1),
            points: [WhiteboardPoint(x: 50, y: 20), WhiteboardPoint(x: 110, y: 20)],
            externalRepresentation: ["startBinding": staleBinding]
        )
        var document = WhiteboardDocument.empty()
        document.elements = [shape, arrow]

        let data = try WhiteboardExcalidrawCodec.encode(document) { _ in nil }
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(root["elements"] as? [[String: Any]])

        #expect(elements[0]["boundElements"] is NSNull)
        #expect(elements[1]["startBinding"] is NSNull)
        #expect(elements[1]["endBinding"] is NSNull)
    }

    @Test("Embedded image limits reject unsafe dimensions and aggregate size")
    func excalidrawEmbeddedImageLimits() throws {
        #expect(throws: WhiteboardExcalidrawError.embeddedImagesTooLarge) {
            try WhiteboardExcalidrawCodec.validatedEmbeddedImagePixelCount(
                width: 32_769,
                height: 1,
                accumulatedPixels: 0
            )
        }
        #expect(throws: WhiteboardExcalidrawError.embeddedImagesTooLarge) {
            try WhiteboardExcalidrawCodec.validatedEmbeddedImagePixelCount(
                width: 10_000,
                height: 10_000,
                accumulatedPixels: 150_000_000
            )
        }
        #expect(
            try WhiteboardExcalidrawCodec.validatedEmbeddedImagePixelCount(
                width: 2_000,
                height: 1_000,
                accumulatedPixels: 0
            ) == 2_000_000
        )
    }

    @Test("Excalidraw keeps file identifiers used by unknown elements")
    func excalidrawUnknownFileRoundTrip() throws {
        let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let source = """
        {
          "type": "excalidraw",
          "version": 2,
          "elements": [{
            "id": "unknown-image-widget",
            "type": "custom-widget",
            "x": 0,
            "y": 0,
            "width": 20,
            "height": 20,
            "fileId": "file-original"
          }],
          "files": {
            "file-original": {
              "id": "file-original",
              "mimeType": "image/png",
              "customMetadata": "kept",
              "dataURL": "data:image/png;base64,\(onePixelPNG)"
            }
          }
        }
        """
        let decoded = try WhiteboardExcalidrawCodec.decode(Data(source.utf8))
        let encoded = try WhiteboardExcalidrawCodec.encode(decoded.document) { resource in
            decoded.embeddedImages.first { $0.resource.id == resource.id }?.data
        }
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let files = try #require(root["files"] as? [String: Any])
        let file = try #require(files["file-original"] as? [String: Any])
        let elements = try #require(root["elements"] as? [[String: Any]])

        #expect(file["customMetadata"] as? String == "kept")
        #expect(elements[0]["fileId"] as? String == "file-original")
    }

    @Test("PNG export uses transparent padded content bounds")
    func pngExportBounds() throws {
        let element = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 10, y: 20),
            size: WhiteboardSize(width: 100, height: 80)
        )
        var document = WhiteboardDocument.empty()
        document.elements = [element]

        let data = try WhiteboardExporter.png(document: document, scale: 1) { _ in nil }
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(image.width == 180)
        #expect(image.height == 160)
        #expect(image.alphaInfo != .none)
        #expect(try rgbaPixel(in: image)[3] == 0)
    }

    @Test("PNG export rejects extreme bounds without trapping")
    func pngExportRejectsExtremeBounds() {
        var document = WhiteboardDocument.empty()
        document.elements = [WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 0, y: 0),
            size: WhiteboardSize(width: 1e100, height: 100)
        )]

        #expect(throws: WhiteboardExportError.self) {
            try WhiteboardExporter.png(document: document) { _ in nil }
        }
    }

    @Test("Excalidraw export clamps extreme timestamps without trapping")
    func excalidrawExportClampsExtremeTimestamps() throws {
        var document = WhiteboardDocument.empty(now: Date(timeIntervalSince1970: 1e100))
        document.elements = [WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 0, y: 0),
            size: WhiteboardSize(width: 10, height: 10),
            updatedAt: Date(timeIntervalSince1970: 1e100)
        )]

        let data = try WhiteboardExcalidrawCodec.encode(document) { _ in nil }
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(root["elements"] as? [[String: Any]])
        #expect(elements[0]["updated"] as? Int == Int.max)
    }

    @Test("Paper export background is applied to PNG and SVG")
    func paperExportBackground() throws {
        let element = WhiteboardElement(
            kind: .rectangle,
            origin: WhiteboardPoint(x: 10, y: 20),
            size: WhiteboardSize(width: 100, height: 80)
        )
        var document = WhiteboardDocument.empty()
        document.elements = [element]

        let png = try WhiteboardExporter.png(
            document: document,
            scale: 1,
            background: .paper
        ) { _ in nil }
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixel = try rgbaPixel(in: image)
        let svgData = WhiteboardExporter.svg(document: document, background: .paper) { _ in nil }
        let svg = try #require(String(data: svgData, encoding: .utf8))

        #expect((248...252).contains(pixel[0]))
        #expect((248...252).contains(pixel[1]))
        #expect((245...250).contains(pixel[2]))
        #expect(pixel[3] == 255)
        #expect(svg.contains("fill=\"#FAFAF7\""))
    }

    private func rgbaPixel(in image: CGImage) throws -> [UInt8] {
        let cropped = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let created = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        #expect(created)
        return pixel
    }
}
