import CoreGraphics
import Foundation

struct WhiteboardPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct WhiteboardSize: Codable, Equatable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

struct WhiteboardCamera: Codable, Equatable, Sendable {
    var offset: WhiteboardPoint
    var zoom: Double

    static let `default` = WhiteboardCamera(
        offset: WhiteboardPoint(x: 0, y: 0),
        zoom: 1
    )

    func normalized() -> WhiteboardCamera {
        WhiteboardCamera(
            offset: WhiteboardPoint(
                x: offset.x.isFinite ? offset.x : 0,
                y: offset.y.isFinite ? offset.y : 0
            ),
            zoom: min(8, max(0.1, zoom.isFinite ? zoom : 1))
        )
    }
}

enum WhiteboardElementKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case ellipse
    case diamond
    case arrow
    case line
    case freehand
    case text
    case image
    case unknown
}

struct WhiteboardElementStyle: Codable, Equatable, Sendable {
    var strokeHex: String
    var fillHex: String?
    var lineWidth: Double
    var opacity: Double
    var fontSize: Double

    static let `default` = WhiteboardElementStyle(
        strokeHex: "#1F2937",
        fillHex: nil,
        lineWidth: 3,
        opacity: 1,
        fontSize: 20
    )

    func normalized() -> WhiteboardElementStyle {
        var value = self
        value.lineWidth = min(40, max(1, lineWidth.isFinite ? lineWidth : 3))
        value.opacity = min(1, max(0.05, opacity.isFinite ? opacity : 1))
        value.fontSize = min(160, max(8, fontSize.isFinite ? fontSize : 20))
        return value
    }
}

struct WhiteboardElementBinding: Codable, Equatable, Sendable {
    var elementID: UUID
    var normalizedPosition: WhiteboardPoint
}

struct WhiteboardElement: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: WhiteboardElementKind
    var origin: WhiteboardPoint
    var size: WhiteboardSize
    var rotation: Double
    var points: [WhiteboardPoint]
    var text: String?
    var imageResourceID: UUID?
    var style: WhiteboardElementStyle
    var createdAt: Date
    var updatedAt: Date
    var externalID: String?
    var externalRepresentation: [String: WhiteboardJSONValue]?
    var startBinding: WhiteboardElementBinding?
    var endBinding: WhiteboardElementBinding?

    init(
        id: UUID = UUID(),
        kind: WhiteboardElementKind,
        origin: WhiteboardPoint,
        size: WhiteboardSize,
        rotation: Double = 0,
        points: [WhiteboardPoint] = [],
        text: String? = nil,
        imageResourceID: UUID? = nil,
        style: WhiteboardElementStyle = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        externalID: String? = nil,
        externalRepresentation: [String: WhiteboardJSONValue]? = nil,
        startBinding: WhiteboardElementBinding? = nil,
        endBinding: WhiteboardElementBinding? = nil
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.size = size
        self.rotation = rotation
        self.points = points
        self.text = text
        self.imageResourceID = imageResourceID
        self.style = style.normalized()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.externalID = externalID
        self.externalRepresentation = externalRepresentation
        self.startBinding = startBinding
        self.endBinding = endBinding
    }

    var frame: CGRect {
        CGRect(
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height
        ).standardized
    }
}

struct WhiteboardImageResource: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var relativePath: String
    var sourceName: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var externalID: String? = nil
    var externalRepresentation: [String: WhiteboardJSONValue]? = nil
}

struct WhiteboardDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var elements: [WhiteboardElement]
    var camera: WhiteboardCamera
    var imageResources: [WhiteboardImageResource]
    var createdAt: Date
    var modifiedAt: Date
    var externalRootExtras: [String: WhiteboardJSONValue]?

    static func empty(now: Date = Date()) -> WhiteboardDocument {
        WhiteboardDocument(
            schemaVersion: currentSchemaVersion,
            id: UUID(),
            elements: [],
            camera: .default,
            imageResources: [],
            createdAt: now,
            modifiedAt: now,
            externalRootExtras: nil
        )
    }

    func normalized() -> WhiteboardDocument {
        var value = self
        value.schemaVersion = Self.currentSchemaVersion
        value.camera = camera.normalized()
        value.elements = elements.map { element in
            var normalized = element
            normalized.style = element.style.normalized()
            normalized.origin = WhiteboardPoint(
                x: element.origin.x.isFinite ? element.origin.x : 0,
                y: element.origin.y.isFinite ? element.origin.y : 0
            )
            normalized.size = WhiteboardSize(
                width: max(1, element.size.width.isFinite ? abs(element.size.width) : 1),
                height: max(1, element.size.height.isFinite ? abs(element.size.height) : 1)
            )
            normalized.rotation = element.rotation.isFinite ? element.rotation : 0
            normalized.points = element.points.compactMap { point in
                guard point.x.isFinite, point.y.isFinite else { return nil }
                return point
            }
            return normalized
        }
        return value
    }
}

enum WhiteboardTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case rectangle
    case ellipse
    case diamond
    case arrow
    case line
    case pen
    case text
    case eraser

    var id: String { rawValue }
}
