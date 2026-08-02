import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class WhiteboardCanvasView: NSView {
    var isEditing = false {
        didSet { needsDisplay = true }
    }

    private(set) var surfaceStyle: WhiteboardSurfaceStyle
    private(set) var guideStyle: WhiteboardGuideStyle
    private let session: WhiteboardSession
    private var cancellables: Set<AnyCancellable> = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var penPoints: [CGPoint] = []
    private var dragOperation: DragOperation?
    private var pasteOffset = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        frame: CGRect,
        session: WhiteboardSession,
        surfaceStyle: WhiteboardSurfaceStyle,
        guideStyle: WhiteboardGuideStyle
    ) {
        self.session = session
        self.surfaceStyle = surfaceStyle
        self.guideStyle = guideStyle
        super.init(frame: frame)
        wantsLayer = true
        layer?.drawsAsynchronously = true
        session.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(
        surfaceStyle: WhiteboardSurfaceStyle,
        guideStyle: WhiteboardGuideStyle
    ) {
        self.surfaceStyle = surfaceStyle
        self.guideStyle = guideStyle
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawBackground(in: context)
        drawEmptyStateIfNeeded()

        let camera = session.document.camera
        context.saveGState()
        context.translateBy(x: camera.offset.x, y: camera.offset.y)
        context.scaleBy(x: camera.zoom, y: camera.zoom)

        let visibleSceneRect = CGRect(
            x: -camera.offset.x / camera.zoom,
            y: -camera.offset.y / camera.zoom,
            width: bounds.width / camera.zoom,
            height: bounds.height / camera.zoom
        ).insetBy(dx: -200, dy: -200)
        for element in session.document.elements
            where WhiteboardGeometry.renderedBounds(for: element).intersects(visibleSceneRect)
        {
            WhiteboardRenderer.draw(
                element: element,
                selected: false,
                image: session.image(for: element.imageResourceID),
                in: context
            )
        }

        if let start = dragStart, let current = dragCurrent,
           let kind = elementKind(for: session.selectedTool)
        {
            WhiteboardRenderer.drawDraft(
                kind: kind,
                start: start,
                current: current,
                points: penPoints,
                style: session.currentStyle,
                in: context
            )
        }

        if isEditing, session.showsSelection {
            drawSelection(in: context)
            drawMarquee(in: context)
        }
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        window?.makeFirstResponder(self)
        let point = scenePoint(forWindowPoint: event.locationInWindow)

        switch session.selectedTool {
        case .select:
            if event.clickCount == 2,
               let hit = hitElement(at: point),
               hit.kind == .text
            {
                promptForText(element: hit)
                return
            }
            beginSelectionInteraction(at: point, event: event)
        case .eraser:
            if let hit = hitElement(at: point) {
                session.remove(ids: [hit.id])
            }
        case .text:
            promptForText(at: point)
        default:
            dragStart = point
            dragCurrent = point
            penPoints = session.selectedTool == .pen ? [point] : []
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }
        let rawPoint = scenePoint(forWindowPoint: event.locationInWindow)
        let point = adjustedDrawingPoint(rawPoint, event: event)

        if session.selectedTool == .eraser {
            if let hit = hitElement(at: point) {
                session.remove(ids: [hit.id])
            }
            return
        }

        switch dragOperation {
        case let .move(_, selectedElements, start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            session.replaceSelectedElementsWithoutHistory(
                selectedElements.map { translated($0, by: delta) }
            )
            return
        case let .resize(_, selectedElements, sourceBounds, handle, rotation, pivot):
            let minimum = 8 / session.document.camera.zoom
            let localPoint = WhiteboardGeometry.rotated(
                point,
                around: pivot,
                by: -rotation
            )
            let resizedBounds = WhiteboardGeometry.resizedBounds(
                sourceBounds,
                handle: handle,
                to: localPoint,
                minimumSize: minimum
            )
            let targetBounds = WhiteboardGeometry.anchoredRotatedResizeBounds(
                original: sourceBounds,
                resized: resizedBounds,
                handle: handle,
                rotation: rotation
            )
            session.replaceSelectedElementsWithoutHistory(selectedElements.map {
                WhiteboardGeometry.transformed($0, from: sourceBounds, to: targetBounds)
            })
            return
        case let .rotate(_, selectedElements, pivot, startAngle):
            let currentAngle = atan2(point.y - pivot.y, point.x - pivot.x)
            var delta = currentAngle - startAngle
            if event.modifierFlags.contains(.shift) {
                let increment = CGFloat.pi / 12
                delta = (delta / increment).rounded() * increment
            }
            session.replaceSelectedElementsWithoutHistory(selectedElements.map {
                WhiteboardGeometry.rotated($0, by: delta, around: pivot)
            })
            return
        case .marquee:
            dragCurrent = point
            needsDisplay = true
            return
        case nil:
            break
        }

        guard dragStart != nil else { return }
        dragCurrent = point
        if session.selectedTool == .pen {
            penPoints.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }

        if session.selectedTool == .select {
            finishSelectionInteraction(at: scenePoint(forWindowPoint: event.locationInWindow))
            return
        }

        guard let start = dragStart else { return }
        let end = adjustedDrawingPoint(
            scenePoint(forWindowPoint: event.locationInWindow),
            event: event
        )
        dragCurrent = end
        if let element = makeElement(from: start, to: end) {
            session.add(element)
        }
        clearDrawingState()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if flags.contains(.command), characters == "z" {
            flags.contains(.shift) ? session.redo() : session.undo()
            return
        }
        if flags.contains(.command), characters == "a" {
            session.selectedElementIDs = Set(session.document.elements.compactMap {
                $0.kind == .unknown ? nil : $0.id
            })
            return
        }
        if flags.contains(.command), characters == "c" {
            copySelection()
            return
        }
        if flags.contains(.command), characters == "x" {
            copySelection()
            session.remove(ids: session.selectedElementIDs)
            return
        }
        if flags.contains(.command), characters == "v" {
            paste()
            return
        }
        if flags.contains(.command), characters == "d" {
            duplicateSelection()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            session.remove(ids: session.selectedElementIDs)
            return
        }
        if event.keyCode == 53 {
            session.clearSelection()
            return
        }
        if let delta = keyboardNudge(for: event) {
            session.translateSelected(by: delta)
            return
        }
        if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
           let characters, let tool = keyboardTool(for: characters)
        {
            session.selectedTool = tool
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEditing else { return }
        if event.modifierFlags.contains(.command) {
            zoom(at: convert(event.locationInWindow, from: nil), factor: exp(-event.scrollingDeltaY * 0.01))
        } else {
            var camera = session.document.camera
            camera.offset.x -= event.scrollingDeltaX
            camera.offset.y -= event.scrollingDeltaY
            session.updateCamera(camera)
        }
    }

    override func magnify(with event: NSEvent) {
        guard isEditing else { return }
        zoom(at: convert(event.locationInWindow, from: nil), factor: 1 + event.magnification)
    }

    func fitContent() {
        guard let content = WhiteboardGeometry.selectionBounds(for: session.document.elements.filter {
            $0.kind != .unknown
        }) else {
            session.updateCamera(.default)
            return
        }
        let padding: CGFloat = 80
        let availableWidth = max(1, bounds.width - padding * 2)
        let availableHeight = max(1, bounds.height - padding * 2)
        let zoom = min(4, max(0.1, min(availableWidth / max(1, content.width), availableHeight / max(1, content.height))))
        session.updateCamera(WhiteboardCamera(
            offset: WhiteboardPoint(
                x: bounds.midX - content.midX * zoom,
                y: bounds.midY - content.midY * zoom
            ),
            zoom: zoom
        ))
    }

    var visibleSceneCenter: CGPoint {
        let camera = session.document.camera
        return CGPoint(
            x: (bounds.midX - camera.offset.x) / camera.zoom,
            y: (bounds.midY - camera.offset.y) / camera.zoom
        )
    }

    private func beginSelectionInteraction(at point: CGPoint, event: NSEvent) {
        let originals = session.document.elements
        let selectedOriginals = originals.filter {
            session.selectedElementIDs.contains($0.id)
        }
        if let geometry = selectionGeometry {
            if let handle = resizeHandle(at: point, geometry: geometry) {
                dragOperation = .resize(
                    historyElements: originals,
                    selectedElements: selectedOriginals,
                    sourceBounds: geometry.bounds,
                    handle: handle,
                    rotation: geometry.rotation,
                    pivot: geometry.pivot
                )
                return
            }
            if isRotationHandle(at: point, geometry: geometry) {
                let pivot = geometry.pivot
                dragOperation = .rotate(
                    historyElements: originals,
                    selectedElements: selectedOriginals,
                    pivot: pivot,
                    startAngle: atan2(point.y - pivot.y, point.x - pivot.x)
                )
                return
            }
        }

        if let hit = hitElement(at: point) {
            if event.modifierFlags.contains(.shift) {
                if session.selectedElementIDs.contains(hit.id) {
                    session.selectedElementIDs.remove(hit.id)
                } else {
                    session.selectedElementIDs.insert(hit.id)
                }
            } else {
                if !session.selectedElementIDs.contains(hit.id) {
                    session.selectedElementIDs = [hit.id]
                }
                session.currentStyle = hit.style
            }
            if session.selectedElementIDs.contains(hit.id) {
                let selected = originals.filter { session.selectedElementIDs.contains($0.id) }
                dragOperation = .move(
                    historyElements: originals,
                    selectedElements: selected,
                    start: point
                )
            }
        } else {
            let additive = event.modifierFlags.contains(.shift)
            if !additive {
                session.clearSelection()
            }
            dragStart = point
            dragCurrent = point
            dragOperation = .marquee(additive: additive)
        }
    }

    private func finishSelectionInteraction(at point: CGPoint) {
        switch dragOperation {
        case let .move(historyElements, _, _),
             let .resize(historyElements, _, _, _, _, _),
             let .rotate(historyElements, _, _, _):
            session.commitTransientChange(from: historyElements)
        case let .marquee(additive):
            dragCurrent = point
            if let marquee = marqueeRect {
                let matches = Set(session.document.elements.compactMap { element in
                    element.kind != .unknown
                        && marquee.intersects(WhiteboardGeometry.renderedBounds(for: element))
                        ? element.id
                        : nil
                })
                session.selectedElementIDs = additive
                    ? session.selectedElementIDs.union(matches)
                    : matches
            }
        case nil:
            break
        }
        dragOperation = nil
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }

    private func drawBackground(in context: CGContext) {
        NSColor.clear.setFill()
        bounds.fill()
        guard isEditing else { return }
        if surfaceStyle == .paper {
            NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 247 / 255, alpha: 0.97)
                .setFill()
            bounds.fill()
        }

        guard guideStyle != .none else { return }
        let camera = session.document.camera
        let spacing = max(10, 24 * camera.zoom)
        let startX = camera.offset.x.truncatingRemainder(dividingBy: spacing)
        let startY = camera.offset.y.truncatingRemainder(dividingBy: spacing)
        context.saveGState()
        let guideColor = surfaceStyle == .paper
            ? NSColor(srgbRed: 0.35, green: 0.38, blue: 0.42, alpha: 0.24)
            : NSColor.labelColor.withAlphaComponent(0.34)
        context.setStrokeColor(guideColor.cgColor)
        context.setFillColor(guideColor.cgColor)
        context.setLineWidth(0.5)
        switch guideStyle {
        case .none:
            break
        case .dots:
            var x = startX
            while x < bounds.maxX {
                var y = startY
                while y < bounds.maxY {
                    context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    y += spacing
                }
                x += spacing
            }
        case .grid:
            context.beginPath()
            var x = startX
            while x < bounds.maxX {
                context.move(to: CGPoint(x: x, y: bounds.minY))
                context.addLine(to: CGPoint(x: x, y: bounds.maxY))
                x += spacing
            }
            var y = startY
            while y < bounds.maxY {
                context.move(to: CGPoint(x: bounds.minX, y: y))
                context.addLine(to: CGPoint(x: bounds.maxX, y: y))
                y += spacing
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawEmptyStateIfNeeded() {
        guard isEditing, session.document.elements.isEmpty else { return }
        let title = WhiteboardLocalization.text("whiteboard.empty.title")
        let subtitle = WhiteboardLocalization.text("whiteboard.empty.subtitle")
        let shortcut = WhiteboardLocalization.text("whiteboard.empty.shortcuts")
        let centerY = bounds.midY - 24
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.82),
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        drawCentered(title, y: centerY - 34, attributes: titleAttributes)
        drawCentered(subtitle, y: centerY + 3, attributes: subtitleAttributes)
        drawCentered(shortcut, y: centerY + 31, attributes: shortcutAttributes)
    }

    private func drawCentered(
        _ text: String,
        y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let size = NSString(string: text).size(withAttributes: attributes)
        NSString(string: text).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: y),
            withAttributes: attributes
        )
    }

    private func drawSelection(in context: CGContext) {
        guard let geometry = selectionGeometry else { return }
        let selectedBounds = geometry.bounds
        let zoom = session.document.camera.zoom
        let lineWidth = 1 / zoom
        let handleSize = 9 / zoom
        context.saveGState()
        context.setAlpha(1)
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [5 / zoom, 4 / zoom])
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        if geometry.rotation != 0 {
            context.translateBy(x: geometry.pivot.x, y: geometry.pivot.y)
            context.rotate(by: geometry.rotation)
            context.translateBy(x: -geometry.pivot.x, y: -geometry.pivot.y)
        }
        context.stroke(selectedBounds.insetBy(dx: -4 / zoom, dy: -4 / zoom))
        context.setLineDash(phase: 0, lengths: [])

        let positions = WhiteboardGeometry.resizeHandlePositions(in: selectedBounds)
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        for point in positions.values {
            let rect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
        let rotationPoint = unrotatedRotationHandlePoint(for: selectedBounds)
        context.beginPath()
        context.move(to: CGPoint(x: selectedBounds.midX, y: selectedBounds.minY))
        context.addLine(to: rotationPoint)
        context.strokePath()
        let rotationRect = CGRect(
            x: rotationPoint.x - handleSize / 2,
            y: rotationPoint.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        context.fillEllipse(in: rotationRect)
        context.strokeEllipse(in: rotationRect)
        context.restoreGState()
    }

    private func drawMarquee(in context: CGContext) {
        guard case .marquee = dragOperation, let marquee = marqueeRect else { return }
        let zoom = session.document.camera.zoom
        context.saveGState()
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
        context.fill(marquee)
        context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1 / zoom)
        context.setLineDash(phase: 0, lengths: [5 / zoom, 4 / zoom])
        context.stroke(marquee)
        context.restoreGState()
    }

    private var selectedElements: [WhiteboardElement] {
        session.document.elements.filter { session.selectedElementIDs.contains($0.id) }
    }

    private var selectionGeometry: SelectionGeometry? {
        let elements = selectedElements
        guard !elements.isEmpty else { return nil }
        if elements.count == 1, let element = elements.first {
            return SelectionGeometry(
                bounds: element.frame,
                rotation: CGFloat(element.rotation),
                pivot: CGPoint(x: element.frame.midX, y: element.frame.midY)
            )
        }
        guard let bounds = WhiteboardGeometry.selectionBounds(for: elements) else { return nil }
        return SelectionGeometry(
            bounds: bounds,
            rotation: 0,
            pivot: CGPoint(x: bounds.midX, y: bounds.midY)
        )
    }

    private var marqueeRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func resizeHandle(at point: CGPoint, geometry: SelectionGeometry) -> WhiteboardResizeHandle? {
        let tolerance = 8 / session.document.camera.zoom
        return WhiteboardGeometry.resizeHandlePositions(in: geometry.bounds).first { _, rawLocation in
            let location = WhiteboardGeometry.rotated(
                rawLocation,
                around: geometry.pivot,
                by: geometry.rotation
            )
            return hypot(point.x - location.x, point.y - location.y) <= tolerance
        }?.key
    }

    private func unrotatedRotationHandlePoint(for bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.minY - 26 / session.document.camera.zoom)
    }

    private func isRotationHandle(at point: CGPoint, geometry: SelectionGeometry) -> Bool {
        let handle = WhiteboardGeometry.rotated(
            unrotatedRotationHandlePoint(for: geometry.bounds),
            around: geometry.pivot,
            by: geometry.rotation
        )
        return hypot(point.x - handle.x, point.y - handle.y) <= 9 / session.document.camera.zoom
    }

    private func scenePoint(forWindowPoint windowPoint: CGPoint) -> CGPoint {
        let point = convert(windowPoint, from: nil)
        let camera = session.document.camera
        return CGPoint(
            x: (point.x - camera.offset.x) / camera.zoom,
            y: (point.y - camera.offset.y) / camera.zoom
        )
    }

    private func hitElement(at point: CGPoint) -> WhiteboardElement? {
        let tolerance = 8 / session.document.camera.zoom
        return session.document.elements.reversed().first {
            WhiteboardGeometry.contains(point, in: $0, tolerance: tolerance)
        }
    }

    private func elementKind(for tool: WhiteboardTool) -> WhiteboardElementKind? {
        switch tool {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .diamond: return .diamond
        case .arrow: return .arrow
        case .line: return .line
        case .pen: return .freehand
        case .select, .text, .eraser: return nil
        }
    }

    private func makeElement(from start: CGPoint, to end: CGPoint) -> WhiteboardElement? {
        guard let kind = elementKind(for: session.selectedTool) else { return nil }
        let inputPoints = kind == .freehand ? penPoints : [start, end]
        guard kind != .freehand || inputPoints.count >= 2 else { return nil }
        guard let first = inputPoints.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in inputPoints.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        if kind != .freehand, hypot(end.x - start.x, end.y - start.y) < 3 {
            return nil
        }
        let points: [WhiteboardPoint]
        switch kind {
        case .arrow, .line:
            points = [WhiteboardPoint(start), WhiteboardPoint(end)]
        case .freehand:
            points = inputPoints.map(WhiteboardPoint.init)
        default:
            points = []
        }
        var element = WhiteboardElement(
            kind: kind,
            origin: WhiteboardPoint(x: minX, y: minY),
            size: WhiteboardSize(width: max(1, maxX - minX), height: max(1, maxY - minY)),
            points: points,
            style: session.currentStyle
        )
        if kind == .arrow || kind == .line {
            element.startBinding = binding(at: start)
            element.endBinding = binding(at: end)
        }
        return element
    }

    private func binding(at point: CGPoint) -> WhiteboardElementBinding? {
        let tolerance = 8 / session.document.camera.zoom
        guard let target = session.document.elements.reversed().first(where: { element in
            switch element.kind {
            case .rectangle, .ellipse, .diamond, .text, .image:
                return WhiteboardGeometry.contains(point, in: element, tolerance: tolerance)
            case .arrow, .line, .freehand, .unknown:
                return false
            }
        }) else { return nil }
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

    private func translated(_ element: WhiteboardElement, by delta: CGPoint) -> WhiteboardElement {
        var value = element
        value.origin.x += delta.x
        value.origin.y += delta.y
        value.points = value.points.map {
            WhiteboardPoint(x: $0.x + delta.x, y: $0.y + delta.y)
        }
        value.updatedAt = Date()
        return value
    }

    private func copySelection() {
        let elements = selectedElements
        guard !elements.isEmpty else { return }
        let selectedResourceIDs = Set(elements.compactMap(\.imageResourceID))
        let images = session.document.imageResources.compactMap { resource -> WhiteboardClipboardImage? in
            guard selectedResourceIDs.contains(resource.id),
                  let data = session.dataForImageResource(resource)
            else { return nil }
            return WhiteboardClipboardImage(resource: resource, data: data)
        }
        let payload = WhiteboardClipboardPayload(elements: elements, images: images)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .whiteboardElements)
        if elements.count == 1, elements[0].kind == .text, let text = elements[0].text {
            pasteboard.setString(text, forType: .string)
        }
        pasteOffset = 0
    }

    private func paste() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .whiteboardElements),
           let payload = try? JSONDecoder().decode(WhiteboardClipboardPayload.self, from: data)
        {
            pasteOffset += 20
            let offset = CGPoint(x: pasteOffset, y: pasteOffset)
            var imageIDMap: [UUID: UUID] = [:]
            for image in payload.images where imageIDMap[image.resource.id] == nil {
                imageIDMap[image.resource.id] = UUID()
            }
            let elements = WhiteboardElementDuplicator.duplicate(
                payload.elements,
                offset: offset
            ).map { element in
                var value = element
                if let resourceID = element.imageResourceID {
                    value.imageResourceID = imageIDMap[resourceID]
                }
                return value
            }
            let images = payload.images.compactMap { image -> (resource: WhiteboardImageResource, data: Data)? in
                guard let id = imageIDMap[image.resource.id] else { return nil }
                var resource = image.resource
                resource.id = id
                resource.relativePath = "Images/\(id.uuidString.lowercased()).png"
                resource.externalID = nil
                resource.externalRepresentation = nil
                return (resource, image.data)
            }
            do {
                try session.insert(elements, embeddedImages: images)
            } catch {
                session.onError?(error)
            }
            return
        }
        if let data = pasteboard.data(forType: .whiteboardElements),
           let legacyElements = try? JSONDecoder().decode([WhiteboardElement].self, from: data)
        {
            pasteOffset += 20
            session.insert(WhiteboardElementDuplicator.duplicate(
                legacyElements,
                offset: CGPoint(x: pasteOffset, y: pasteOffset)
            ))
            return
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { continue }
            do {
                try session.addImage(cgImage, sourceName: nil, center: visibleSceneCenter)
            } catch {
                session.onError?(error)
            }
            return
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let element = WhiteboardElement(
                kind: .text,
                origin: WhiteboardPoint(x: visibleSceneCenter.x - 100, y: visibleSceneCenter.y - 20),
                size: WhiteboardSize(width: max(80, Double(text.count) * session.currentStyle.fontSize * 0.65), height: session.currentStyle.fontSize * 1.5),
                text: text,
                style: session.currentStyle
            )
            session.add(element)
        }
    }

    private func duplicateSelection() {
        let elements = WhiteboardElementDuplicator.duplicate(
            selectedElements,
            offset: CGPoint(x: 20, y: 20)
        )
        session.insert(elements)
    }

    private func keyboardNudge(for event: NSEvent) -> CGPoint? {
        let distance: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: return CGPoint(x: -distance, y: 0)
        case 124: return CGPoint(x: distance, y: 0)
        case 125: return CGPoint(x: 0, y: distance)
        case 126: return CGPoint(x: 0, y: -distance)
        default: return nil
        }
    }

    private func keyboardTool(for character: String) -> WhiteboardTool? {
        switch character {
        case "v": return .select
        case "r": return .rectangle
        case "o": return .ellipse
        case "d": return .diamond
        case "a": return .arrow
        case "l": return .line
        case "p": return .pen
        case "t": return .text
        case "e": return .eraser
        default: return nil
        }
    }

    private func adjustedDrawingPoint(_ point: CGPoint, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift), let start = dragStart else { return point }
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch session.selectedTool {
        case .rectangle, .ellipse, .diamond:
            let length = max(abs(dx), abs(dy))
            return CGPoint(
                x: start.x + (dx < 0 ? -length : length),
                y: start.y + (dy < 0 ? -length : length)
            )
        case .arrow, .line:
            let length = hypot(dx, dy)
            let angle = (atan2(dy, dx) / (CGFloat.pi / 4)).rounded() * (CGFloat.pi / 4)
            return CGPoint(
                x: start.x + cos(angle) * length,
                y: start.y + sin(angle) * length
            )
        case .select, .pen, .text, .eraser:
            return point
        }
    }

    private func zoom(at pointer: CGPoint, factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        var camera = session.document.camera
        let sceneBefore = CGPoint(
            x: (pointer.x - camera.offset.x) / camera.zoom,
            y: (pointer.y - camera.offset.y) / camera.zoom
        )
        camera.zoom = min(8, max(0.1, camera.zoom * factor))
        camera.offset.x = pointer.x - sceneBefore.x * camera.zoom
        camera.offset.y = pointer.y - sceneBefore.y * camera.zoom
        session.updateCamera(camera)
    }

    private func clearDrawingState() {
        dragStart = nil
        dragCurrent = nil
        penPoints = []
    }

    private func promptForText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = WhiteboardLocalization.text("whiteboard.text.add")
        alert.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.add"))
        alert.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = WhiteboardLocalization.text("whiteboard.text.placeholder")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let width = max(80, Double(text.count) * session.currentStyle.fontSize * 0.65)
        session.add(WhiteboardElement(
            kind: .text,
            origin: WhiteboardPoint(point),
            size: WhiteboardSize(width: width, height: session.currentStyle.fontSize * 1.5),
            text: text,
            style: session.currentStyle
        ))
    }

    private func promptForText(element: WhiteboardElement) {
        let alert = NSAlert()
        alert.messageText = WhiteboardLocalization.text("whiteboard.text.edit")
        alert.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.save"))
        alert.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = element.text ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.updateText(
            id: element.id,
            text: text,
            size: WhiteboardSize(
                width: max(80, Double(text.count) * element.style.fontSize * 0.65),
                height: element.style.fontSize * 1.5
            )
        )
    }
}

private enum DragOperation {
    case move(
        historyElements: [WhiteboardElement],
        selectedElements: [WhiteboardElement],
        start: CGPoint
    )
    case resize(
        historyElements: [WhiteboardElement],
        selectedElements: [WhiteboardElement],
        sourceBounds: CGRect,
        handle: WhiteboardResizeHandle,
        rotation: CGFloat,
        pivot: CGPoint
    )
    case rotate(
        historyElements: [WhiteboardElement],
        selectedElements: [WhiteboardElement],
        pivot: CGPoint,
        startAngle: CGFloat
    )
    case marquee(additive: Bool)
}

private struct SelectionGeometry {
    let bounds: CGRect
    let rotation: CGFloat
    let pivot: CGPoint
}

private struct WhiteboardClipboardPayload: Codable {
    let elements: [WhiteboardElement]
    let images: [WhiteboardClipboardImage]
}

private struct WhiteboardClipboardImage: Codable {
    let resource: WhiteboardImageResource
    let data: Data
}

enum WhiteboardElementDuplicator {
    static func duplicate(
        _ source: [WhiteboardElement],
        offset: CGPoint
    ) -> [WhiteboardElement] {
        var idMap: [UUID: UUID] = [:]
        for element in source where idMap[element.id] == nil {
            idMap[element.id] = UUID()
        }
        return source.map { element in
            var value = element
            value.origin.x += offset.x
            value.origin.y += offset.y
            value.points = value.points.map {
                WhiteboardPoint(x: $0.x + offset.x, y: $0.y + offset.y)
            }
            value.id = idMap[element.id] ?? UUID()
            value.startBinding = remappedBinding(element.startBinding, using: idMap)
            value.endBinding = remappedBinding(element.endBinding, using: idMap)
            value.externalID = nil
            if var representation = value.externalRepresentation {
                representation.removeValue(forKey: "startBinding")
                representation.removeValue(forKey: "endBinding")
                representation.removeValue(forKey: "boundElements")
                value.externalRepresentation = representation
            }
            value.createdAt = Date()
            value.updatedAt = value.createdAt
            return value
        }
    }

    private static func remappedBinding(
        _ binding: WhiteboardElementBinding?,
        using idMap: [UUID: UUID]
    ) -> WhiteboardElementBinding? {
        guard var binding, let remappedID = idMap[binding.elementID] else { return nil }
        binding.elementID = remappedID
        return binding
    }
}

private extension NSPasteboard.PasteboardType {
    static let whiteboardElements = NSPasteboard.PasteboardType(
        "tech.lury.meow.whiteboard.elements"
    )
}
