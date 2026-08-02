import Foundation
import ImageIO

enum WhiteboardExcalidrawError: LocalizedError, Equatable {
    case invalidRoot
    case invalidElements
    case duplicateElementID(String)
    case embeddedImagesTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            return String(localized: "whiteboard.error.excalidraw.root", bundle: .module)
        case .invalidElements:
            return String(localized: "whiteboard.error.excalidraw.elements", bundle: .module)
        case let .duplicateElementID(id):
            return String(
                format: String(localized: "whiteboard.error.excalidraw.duplicate.id", bundle: .module),
                id
            )
        case .embeddedImagesTooLarge:
            return String(localized: "whiteboard.error.excalidraw.images.too.large", bundle: .module)
        }
    }
}

struct WhiteboardDecodedExcalidraw {
    var document: WhiteboardDocument
    var embeddedImages: [(resource: WhiteboardImageResource, data: Data)]
}

enum WhiteboardExcalidrawCodec {
    static func decode(_ data: Data) throws -> WhiteboardDecodedExcalidraw {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhiteboardExcalidrawError.invalidRoot
        }
        guard let rawElements = root["elements"] as? [[String: Any]] else {
            throw WhiteboardExcalidrawError.invalidElements
        }

        let decodedImages = try decodeEmbeddedImages(root["files"])
        let fileIDMap = Dictionary(uniqueKeysWithValues: decodedImages.map {
            ($0.externalID, $0.resource.id)
        })
        var elements: [WhiteboardElement] = []
        var usedExternalIDs: Set<String> = []
        var usedElementIDs: Set<UUID> = []
        for raw in rawElements {
            guard (raw["isDeleted"] as? Bool) != true else { continue }
            let type = raw["type"] as? String ?? "unknown"
            let kind = kind(for: type)
            let x = number(raw["x"])
            let y = number(raw["y"])
            let width = max(1, number(raw["width"]))
            let height = max(1, number(raw["height"]))
            let externalID = raw["id"] as? String
            if let externalID, !usedExternalIDs.insert(externalID).inserted {
                throw WhiteboardExcalidrawError.duplicateElementID(externalID)
            }
            let id = externalID.flatMap(UUID.init(uuidString:)) ?? UUID()
            guard usedElementIDs.insert(id).inserted else {
                throw WhiteboardExcalidrawError.duplicateElementID(externalID ?? id.uuidString)
            }
            let rawPoints = raw["points"] as? [[Any]] ?? []
            let points = rawPoints.compactMap { pair -> WhiteboardPoint? in
                guard pair.count >= 2 else { return nil }
                return WhiteboardPoint(
                    x: x + number(pair[0]),
                    y: y + number(pair[1])
                )
            }
            let stroke = raw["strokeColor"] as? String ?? WhiteboardElementStyle.default.strokeHex
            let background = raw["backgroundColor"] as? String
            let fill = background == "transparent" ? nil : background
            let opacity = min(1, max(0.05, number(raw["opacity"], fallback: 100) / 100))
            let updatedMilliseconds = number(raw["updated"], fallback: Date().timeIntervalSince1970 * 1_000)
            let timestamp = Date(timeIntervalSince1970: updatedMilliseconds / 1_000)
            let externalFileID = raw["fileId"] as? String
            elements.append(WhiteboardElement(
                id: id,
                kind: kind,
                origin: WhiteboardPoint(x: x, y: y),
                size: WhiteboardSize(width: width, height: height),
                rotation: number(raw["angle"]),
                points: points,
                text: raw["text"] as? String,
                imageResourceID: externalFileID.flatMap { fileIDMap[$0] },
                style: WhiteboardElementStyle(
                    strokeHex: stroke,
                    fillHex: fill,
                    lineWidth: number(raw["strokeWidth"], fallback: 2),
                    opacity: opacity,
                    fontSize: number(raw["fontSize"], fallback: 20)
                ),
                createdAt: timestamp,
                updatedAt: timestamp,
                externalID: externalID,
                externalRepresentation: raw.mapValues(WhiteboardJSONValue.init(any:))
            ))
        }
        let elementsByExternalID = Dictionary(uniqueKeysWithValues: elements.compactMap { element in
            element.externalID.map { ($0, element) }
        })
        for index in elements.indices where elements[index].kind == .arrow || elements[index].kind == .line {
            guard elements[index].points.count >= 2 else { continue }
            if let externalID = bindingExternalID(
                from: elements[index].externalRepresentation?["startBinding"]
            ), let target = elementsByExternalID[externalID] {
                elements[index].startBinding = binding(
                    to: target,
                    at: elements[index].points[0].cgPoint
                )
            }
            if let externalID = bindingExternalID(
                from: elements[index].externalRepresentation?["endBinding"]
            ), let target = elementsByExternalID[externalID] {
                elements[index].endBinding = binding(
                    to: target,
                    at: elements[index].points[elements[index].points.count - 1].cgPoint
                )
            }
        }

        var rootExtras = root
        rootExtras.removeValue(forKey: "elements")
        rootExtras.removeValue(forKey: "files")
        let now = Date()
        let document = WhiteboardDocument(
            schemaVersion: WhiteboardDocument.currentSchemaVersion,
            id: UUID(),
            elements: elements,
            camera: .default,
            imageResources: decodedImages.map(\.resource),
            createdAt: now,
            modifiedAt: now,
            externalRootExtras: rootExtras.mapValues(WhiteboardJSONValue.init(any:))
        )
        return WhiteboardDecodedExcalidraw(
            document: document,
            embeddedImages: decodedImages.map { ($0.resource, $0.data) }
        )
    }

    static func encode(
        _ document: WhiteboardDocument,
        imageData: (WhiteboardImageResource) -> Data?
    ) throws -> Data {
        var root = document.externalRootExtras?.mapValues(\.anyValue) ?? [:]
        root["type"] = "excalidraw"
        root["version"] = 2
        root["source"] = "meow"
        if root["appState"] == nil {
            root["appState"] = [
                "viewBackgroundColor": "#ffffff",
                "gridSize": 20,
            ] as [String: Any]
        }
        var externalIDs: [UUID: String] = [:]
        var exportedElementIDs: Set<String> = []
        for element in document.elements {
            let externalID = element.externalID ?? element.id.uuidString.lowercased()
            guard externalIDs[element.id] == nil,
                  exportedElementIDs.insert(externalID).inserted
            else {
                throw WhiteboardExcalidrawError.duplicateElementID(externalID)
            }
            externalIDs[element.id] = externalID
        }
        var imageExternalIDs: [UUID: String] = [:]
        for resource in document.imageResources where imageExternalIDs[resource.id] == nil {
            imageExternalIDs[resource.id] = resource.externalID
                ?? resource.id.uuidString.lowercased()
        }
        var boundElementsByTarget: [UUID: [[String: Any]]] = [:]
        for element in document.elements where element.kind == .arrow || element.kind == .line {
            guard let elementExternalID = externalIDs[element.id] else { continue }
            let reference: [String: Any] = [
                "id": elementExternalID,
                "type": externalType(for: element.kind),
            ]
            if let targetID = element.startBinding?.elementID {
                boundElementsByTarget[targetID, default: []].append(reference)
            }
            if let targetID = element.endBinding?.elementID,
               targetID != element.startBinding?.elementID
            {
                boundElementsByTarget[targetID, default: []].append(reference)
            }
        }
        root["elements"] = document.elements.map {
            encodeElement(
                $0,
                externalIDs: externalIDs,
                imageExternalIDs: imageExternalIDs,
                boundElements: boundElementsByTarget[$0.id]
            )
        }

        var files: [String: Any] = [:]
        for resource in document.imageResources {
            guard let data = imageData(resource) else { continue }
            let id = imageExternalIDs[resource.id] ?? resource.id.uuidString.lowercased()
            var file = resource.externalRepresentation?.mapValues(\.anyValue) ?? [:]
            file["mimeType"] = "image/png"
            file["id"] = id
            file["dataURL"] = "data:image/png;base64,\(data.base64EncodedString())"
            file["created"] = file["created"]
                ?? Int(document.modifiedAt.timeIntervalSince1970 * 1_000)
            file["lastRetrieved"] = Int(document.modifiedAt.timeIntervalSince1970 * 1_000)
            files[id] = file
        }
        if !files.isEmpty {
            root["files"] = files
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func encodeElement(
        _ element: WhiteboardElement,
        externalIDs: [UUID: String],
        imageExternalIDs: [UUID: String],
        boundElements: [[String: Any]]?
    ) -> [String: Any] {
        if element.kind == .unknown, let raw = element.externalRepresentation {
            return raw.mapValues(\.anyValue)
        }
        var raw = element.externalRepresentation?.mapValues(\.anyValue) ?? [:]
        let id = element.externalID ?? element.id.uuidString.lowercased()
        let type = externalType(for: element.kind)
        raw["id"] = id
        raw["type"] = type
        raw["x"] = element.origin.x
        raw["y"] = element.origin.y
        raw["width"] = element.size.width
        raw["height"] = element.size.height
        raw["angle"] = element.rotation
        raw["strokeColor"] = element.style.strokeHex
        raw["backgroundColor"] = element.style.fillHex ?? "transparent"
        raw["fillStyle"] = "solid"
        raw["strokeWidth"] = element.style.lineWidth
        raw["strokeStyle"] = "solid"
        raw["roughness"] = 1
        raw["opacity"] = Int(element.style.opacity * 100)
        raw["seed"] = stableSeed(for: id)
        raw["version"] = max(1, raw["version"] as? Int ?? 1)
        raw["versionNonce"] = stableSeed(for: id + "-version")
        raw["isDeleted"] = false
        raw["groupIds"] = raw["groupIds"] ?? []
        raw["frameId"] = raw["frameId"] ?? NSNull()
        if let boundElements, !boundElements.isEmpty {
            raw["boundElements"] = boundElements
        } else {
            raw["boundElements"] = NSNull()
        }
        raw["updated"] = Int(element.updatedAt.timeIntervalSince1970 * 1_000)
        raw["link"] = raw["link"] ?? NSNull()
        raw["locked"] = false

        if element.kind == .arrow || element.kind == .line || element.kind == .freehand {
            raw["points"] = element.points.map { point in
                [point.x - element.origin.x, point.y - element.origin.y]
            }
        }
        if element.kind == .arrow {
            raw["startArrowhead"] = raw["startArrowhead"] ?? NSNull()
            raw["endArrowhead"] = "arrow"
        }
        if element.kind == .arrow || element.kind == .line {
            if let startBinding = element.startBinding {
                raw["startBinding"] = encodedBinding(startBinding, externalIDs: externalIDs)
            } else {
                raw["startBinding"] = NSNull()
            }
            if let endBinding = element.endBinding {
                raw["endBinding"] = encodedBinding(endBinding, externalIDs: externalIDs)
            } else {
                raw["endBinding"] = NSNull()
            }
        }
        if element.kind == .text {
            raw["text"] = element.text ?? ""
            raw["originalText"] = element.text ?? ""
            raw["fontSize"] = element.style.fontSize
            raw["fontFamily"] = 1
            raw["textAlign"] = "left"
            raw["verticalAlign"] = "top"
            raw["lineHeight"] = 1.25
            raw["containerId"] = raw["containerId"] ?? NSNull()
        }
        if element.kind == .image, let resourceID = element.imageResourceID {
            raw["fileId"] = imageExternalIDs[resourceID] ?? resourceID.uuidString.lowercased()
            raw["status"] = "saved"
            raw["scale"] = [1, 1]
        }
        return raw
    }

    private static func decodeEmbeddedImages(
        _ rawFiles: Any?
    ) throws -> [(externalID: String, resource: WhiteboardImageResource, data: Data)] {
        guard let files = rawFiles as? [String: Any] else { return [] }
        var decoded: [(externalID: String, resource: WhiteboardImageResource, data: Data)] = []
        var totalPixels: Double = 0
        for (externalID, raw) in files {
            guard let object = raw as? [String: Any],
                  let dataURL = object["dataURL"] as? String,
                  let comma = dataURL.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
            else { continue }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { continue }
            let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let pixelCount = try validatedEmbeddedImagePixelCount(
                width: pixelWidth,
                height: pixelHeight,
                accumulatedPixels: totalPixels
            )
            totalPixels += pixelCount
            let id = UUID()
            var representation = object
            representation.removeValue(forKey: "dataURL")
            let resource = WhiteboardImageResource(
                id: id,
                relativePath: "Images/\(id.uuidString.lowercased()).png",
                sourceName: nil,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                externalID: externalID,
                externalRepresentation: representation.mapValues(WhiteboardJSONValue.init(any:))
            )
            decoded.append((externalID, resource, data))
        }
        return decoded
    }

    static func validatedEmbeddedImagePixelCount(
        width: Int,
        height: Int,
        accumulatedPixels: Double
    ) throws -> Double {
        let pixelCount = Double(width) * Double(height)
        guard width > 0,
              height > 0,
              width <= 32_768,
              height <= 32_768,
              pixelCount <= 100_000_000,
              accumulatedPixels + pixelCount <= 200_000_000
        else {
            throw WhiteboardExcalidrawError.embeddedImagesTooLarge
        }
        return pixelCount
    }

    private static func bindingExternalID(from value: WhiteboardJSONValue?) -> String? {
        guard case let .object(binding)? = value,
              case let .string(elementID)? = binding["elementId"]
        else { return nil }
        return elementID
    }

    private static func binding(
        to target: WhiteboardElement,
        at point: CGPoint
    ) -> WhiteboardElementBinding {
        let frame = target.frame
        let local = WhiteboardGeometry.rotated(
            point,
            around: CGPoint(x: frame.midX, y: frame.midY),
            by: -CGFloat(target.rotation)
        )
        return WhiteboardElementBinding(
            elementID: target.id,
            normalizedPosition: WhiteboardPoint(
                x: min(1, max(0, (local.x - frame.minX) / max(1, frame.width))),
                y: min(1, max(0, (local.y - frame.minY) / max(1, frame.height)))
            )
        )
    }

    private static func encodedBinding(
        _ binding: WhiteboardElementBinding,
        externalIDs: [UUID: String]
    ) -> Any {
        guard let elementID = externalIDs[binding.elementID] else {
            return NSNull()
        }
        return [
            "elementId": elementID,
            "focus": 0,
            "gap": 0,
            "fixedPoint": [binding.normalizedPosition.x, binding.normalizedPosition.y],
        ] as [String: Any]
    }

    private static func kind(for externalType: String) -> WhiteboardElementKind {
        switch externalType {
        case "rectangle": return .rectangle
        case "ellipse": return .ellipse
        case "diamond": return .diamond
        case "arrow": return .arrow
        case "line": return .line
        case "freedraw": return .freehand
        case "text": return .text
        case "image": return .image
        default: return .unknown
        }
    }

    private static func externalType(for kind: WhiteboardElementKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .diamond: return "diamond"
        case .arrow: return "arrow"
        case .line: return "line"
        case .freehand: return "freedraw"
        case .text: return "text"
        case .image: return "image"
        case .unknown: return "unknown"
        }
    }

    private static func number(_ value: Any?, fallback: Double = 0) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return fallback
    }

    private static func stableSeed(for value: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Int(hash & 0x7FFF_FFFF)
    }
}
