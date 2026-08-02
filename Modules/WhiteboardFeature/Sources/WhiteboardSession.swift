import AppKit
import Combine
import Foundation
import ImageIO

@MainActor
final class WhiteboardSession: ObservableObject {
    @Published private(set) var document: WhiteboardDocument
    @Published var selectedTool: WhiteboardTool = .select
    @Published var selectedElementIDs: Set<UUID> = []
    @Published var currentStyle: WhiteboardElementStyle = .default
    @Published var showsSelection = true

    var onDocumentChanged: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let store: WhiteboardDocumentStore
    private var undoStack: [WhiteboardHistorySnapshot] = []
    private var redoStack: [WhiteboardHistorySnapshot] = []
    private var autosaveTask: Task<Void, Never>?
    private var hasUnsavedChanges = false
    private var imageCache: [UUID: CGImage] = [:]
    private var lastStyleMutationAt: Date?

    init(document: WhiteboardDocument, store: WhiteboardDocumentStore) {
        var normalized = document.normalized()
        Self.synchronizeBindings(in: &normalized.elements)
        self.document = normalized
        self.store = store
    }

    deinit {
        autosaveTask?.cancel()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ element: WhiteboardElement) {
        mutateElements { $0.append(element) }
        selectedElementIDs = [element.id]
    }

    func insert(_ elements: [WhiteboardElement]) {
        guard !elements.isEmpty else { return }
        mutateElements { $0.append(contentsOf: elements) }
        selectedElementIDs = Set(elements.map(\.id))
    }

    func insert(
        _ elements: [WhiteboardElement],
        embeddedImages: [(resource: WhiteboardImageResource, data: Data)]
    ) throws {
        guard !elements.isEmpty else { return }
        let previous = historySnapshot()
        try saveEmbeddedImages(embeddedImages)
        document.imageResources.append(contentsOf: embeddedImages.map(\.resource))
        document.elements.append(contentsOf: elements)
        Self.synchronizeBindings(in: &document.elements)
        pruneUnreferencedImageResources()
        pushUndo(previous)
        redoStack.removeAll()
        selectedElementIDs = Set(elements.map(\.id))
        markChanged()
    }

    func addImage(
        _ image: CGImage,
        sourceName: String?,
        center: CGPoint
    ) throws {
        guard Double(image.width) * Double(image.height) <= 100_000_000 else {
            throw NSError(
                domain: "tech.lury.meow.whiteboard",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: WhiteboardLocalization.text("whiteboard.error.image.too.large"),
                ]
            )
        }
        let id = UUID()
        let url = try store.saveImage(image, id: id)
        let relativePath = url.path.replacingOccurrences(
            of: store.directory.path + "/",
            with: ""
        )
        let resource = WhiteboardImageResource(
            id: id,
            relativePath: relativePath,
            sourceName: sourceName,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        let maxDimension: CGFloat = 640
        let naturalSize = CGSize(width: image.width, height: image.height)
        let scale = min(1, maxDimension / max(naturalSize.width, naturalSize.height))
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let element = WhiteboardElement(
            kind: .image,
            origin: WhiteboardPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            size: WhiteboardSize(width: size.width, height: size.height),
            imageResourceID: id,
            style: currentStyle
        )
        let previous = historySnapshot()
        document.imageResources.append(resource)
        document.elements.append(element)
        imageCache[id] = Self.previewImage(at: url) ?? image
        pushUndo(previous)
        redoStack.removeAll()
        selectedElementIDs = [element.id]
        markChanged()
    }

    func replaceDocument(
        _ document: WhiteboardDocument,
        embeddedImages: [(resource: WhiteboardImageResource, data: Data)]
    ) throws {
        try saveEmbeddedImages(embeddedImages)
        undoStack.removeAll()
        redoStack.removeAll()
        selectedElementIDs.removeAll()
        imageCache.removeAll()
        var normalized = document.normalized()
        Self.synchronizeBindings(in: &normalized.elements)
        self.document = normalized
        hasUnsavedChanges = true
        try forceSave()
        objectWillChange.send()
        onDocumentChanged?()
    }

    func dataForImageResource(_ resource: WhiteboardImageResource) -> Data? {
        store.imageData(for: resource)
    }

    func image(for resourceID: UUID?) -> CGImage? {
        guard let resourceID else { return nil }
        if let cached = imageCache[resourceID] { return cached }
        guard let resource = document.imageResources.first(where: { $0.id == resourceID }),
              let image = Self.previewImage(at: store.imageURL(for: resource))
        else { return nil }
        imageCache[resourceID] = image
        return image
    }

    func fullResolutionImage(for resourceID: UUID?) -> CGImage? {
        guard let resourceID,
              let resource = document.imageResources.first(where: { $0.id == resourceID }),
              let source = CGImageSourceCreateWithURL(store.imageURL(for: resource) as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutateElements { elements in
            elements.removeAll { ids.contains($0.id) }
        }
        selectedElementIDs.subtract(ids)
    }

    func replaceSelectedElementsWithoutHistory(_ replacements: [WhiteboardElement]) {
        var replacementsByID: [UUID: WhiteboardElement] = [:]
        for element in replacements {
            replacementsByID[element.id] = element
        }
        for index in document.elements.indices {
            guard let replacement = replacementsByID[document.elements[index].id] else { continue }
            document.elements[index] = replacement
        }
        Self.synchronizeBindings(in: &document.elements)
        document.modifiedAt = Date()
        objectWillChange.send()
        onDocumentChanged?()
    }

    func commitTransientChange(from originalElements: [WhiteboardElement]) {
        guard originalElements != document.elements else { return }
        pushUndo(WhiteboardHistorySnapshot(
            elements: originalElements,
            imageResources: document.imageResources
        ))
        redoStack.removeAll()
        markChanged()
    }

    func updateSelectedStyle(_ style: WhiteboardElementStyle) {
        let normalized = style.normalized()
        currentStyle = normalized
        guard !selectedElementIDs.isEmpty else { return }
        let previous = historySnapshot()
        for index in document.elements.indices where selectedElementIDs.contains(document.elements[index].id) {
            document.elements[index].style = normalized
            document.elements[index].updatedAt = Date()
        }
        guard previous.elements != document.elements else { return }
        let now = Date()
        if lastStyleMutationAt.map({ now.timeIntervalSince($0) > 0.5 }) ?? true {
            pushUndo(previous)
        }
        lastStyleMutationAt = now
        redoStack.removeAll()
        markChanged()
    }

    func updateText(id: UUID, text: String, size: WhiteboardSize) {
        mutateElements { elements in
            guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
            elements[index].text = text
            elements[index].size = size
            elements[index].updatedAt = Date()
        }
    }

    func clearSelection() {
        selectedElementIDs.removeAll()
    }

    func translateSelected(by delta: CGPoint) {
        guard !selectedElementIDs.isEmpty, delta != .zero else { return }
        mutateElements { elements in
            for index in elements.indices where selectedElementIDs.contains(elements[index].id) {
                elements[index].origin.x += delta.x
                elements[index].origin.y += delta.y
                elements[index].points = elements[index].points.map {
                    WhiteboardPoint(x: $0.x + delta.x, y: $0.y + delta.y)
                }
                elements[index].updatedAt = Date()
            }
        }
    }

    func undo() {
        lastStyleMutationAt = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(historySnapshot())
        document.elements = previous.elements
        document.imageResources = previous.imageResources
        Self.synchronizeBindings(in: &document.elements)
        selectedElementIDs = selectedElementIDs.intersection(Set(previous.elements.map(\.id)))
        markChanged()
    }

    func redo() {
        lastStyleMutationAt = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(historySnapshot())
        document.elements = next.elements
        document.imageResources = next.imageResources
        Self.synchronizeBindings(in: &document.elements)
        selectedElementIDs = selectedElementIDs.intersection(Set(next.elements.map(\.id)))
        markChanged()
    }

    func updateCamera(_ camera: WhiteboardCamera) {
        document.camera = camera.normalized()
        markChanged(scheduleAutosave: true)
    }

    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges else { return }
        do {
            try store.save(
                document,
                preservingImageResourceIDs: imageResourceIDsNeededByHistory
            )
            hasUnsavedChanges = false
        } catch {
            onError?(error)
        }
    }

    func forceSave() throws {
        autosaveTask?.cancel()
        autosaveTask = nil
        try store.save(
            document,
            preservingImageResourceIDs: imageResourceIDsNeededByHistory
        )
        hasUnsavedChanges = false
    }

    func close() {
        autosaveTask?.cancel()
        autosaveTask = nil
        undoStack.removeAll()
        redoStack.removeAll()
        pruneUnreferencedImageResources()
        do {
            try store.save(document)
            hasUnsavedChanges = false
        } catch {
            onError?(error)
        }
    }

    private func mutateElements(_ mutation: (inout [WhiteboardElement]) -> Void) {
        lastStyleMutationAt = nil
        let previous = historySnapshot()
        mutation(&document.elements)
        Self.synchronizeBindings(in: &document.elements)
        pruneUnreferencedImageResources()
        guard previous.elements != document.elements
                || previous.imageResources != document.imageResources
        else { return }
        pushUndo(previous)
        redoStack.removeAll()
        markChanged()
    }

    private func pushUndo(_ snapshot: WhiteboardHistorySnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
    }

    private func markChanged(scheduleAutosave: Bool = true) {
        document.modifiedAt = Date()
        hasUnsavedChanges = true
        objectWillChange.send()
        onDocumentChanged?()
        if scheduleAutosave {
            scheduleAutosaveTask()
        }
    }

    private func historySnapshot() -> WhiteboardHistorySnapshot {
        WhiteboardHistorySnapshot(
            elements: document.elements,
            imageResources: document.imageResources
        )
    }

    private func saveEmbeddedImages(
        _ embeddedImages: [(resource: WhiteboardImageResource, data: Data)]
    ) throws {
        do {
            for embedded in embeddedImages {
                _ = try store.savePNGData(embedded.data, id: embedded.resource.id)
            }
        } catch {
            try? store.save(
                document,
                preservingImageResourceIDs: imageResourceIDsNeededByHistory
            )
            throw error
        }
    }

    private var imageResourceIDsNeededByHistory: Set<UUID> {
        Set((undoStack + redoStack).flatMap { snapshot in
            snapshot.imageResources.map(\.id)
        })
    }

    private func pruneUnreferencedImageResources() {
        let directlyReferenced = Set(document.elements.compactMap(\.imageResourceID))
        let externallyReferenced = Set(document.elements.compactMap { element -> String? in
            guard case let .string(fileID)? = element.externalRepresentation?["fileId"] else {
                return nil
            }
            return fileID
        })
        document.imageResources.removeAll { resource in
            let isExternallyReferenced = resource.externalID.map {
                externallyReferenced.contains($0)
            } ?? false
            return !directlyReferenced.contains(resource.id)
                && !isExternallyReferenced
        }
    }

    private func scheduleAutosaveTask() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private static func previewImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func synchronizeBindings(in elements: inout [WhiteboardElement]) {
        var targets: [UUID: WhiteboardElement] = [:]
        for element in elements where isBindingTarget(element) && targets[element.id] == nil {
            targets[element.id] = element
        }
        for index in elements.indices where elements[index].kind == .arrow || elements[index].kind == .line {
            guard elements[index].points.count >= 2 else { continue }
            if let binding = elements[index].startBinding {
                if let target = targets[binding.elementID] {
                    elements[index].points[0] = WhiteboardPoint(anchor(for: binding, in: target))
                } else {
                    elements[index].startBinding = nil
                }
            }
            if let binding = elements[index].endBinding {
                if let target = targets[binding.elementID] {
                    elements[index].points[elements[index].points.count - 1] = WhiteboardPoint(
                        anchor(for: binding, in: target)
                    )
                } else {
                    elements[index].endBinding = nil
                }
            }
            guard let first = elements[index].points.first?.cgPoint else { continue }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in elements[index].points.dropFirst().map(\.cgPoint) {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            elements[index].origin = WhiteboardPoint(x: minX, y: minY)
            elements[index].size = WhiteboardSize(
                width: max(1, maxX - minX),
                height: max(1, maxY - minY)
            )
        }
    }

    private static func isBindingTarget(_ element: WhiteboardElement) -> Bool {
        switch element.kind {
        case .rectangle, .ellipse, .diamond, .text, .image: return true
        case .arrow, .line, .freehand, .unknown: return false
        }
    }

    private static func anchor(
        for binding: WhiteboardElementBinding,
        in element: WhiteboardElement
    ) -> CGPoint {
        let frame = element.frame
        let local = CGPoint(
            x: frame.minX + frame.width * binding.normalizedPosition.x,
            y: frame.minY + frame.height * binding.normalizedPosition.y
        )
        return WhiteboardGeometry.rotated(
            local,
            around: CGPoint(x: frame.midX, y: frame.midY),
            by: CGFloat(element.rotation)
        )
    }
}

private struct WhiteboardHistorySnapshot: Equatable {
    let elements: [WhiteboardElement]
    let imageResources: [WhiteboardImageResource]
}
