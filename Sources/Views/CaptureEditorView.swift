import AppKit
import SwiftUI

struct CaptureEditorView: View {
    let source: CGImage
    @ObservedObject var model: CaptureEditorModel
    let onCancel: () -> Void
    let onFinish: (CGImage) -> Void

    @State private var pendingTextPoint: CGPoint?
    @State private var textInput = ""
    @State private var errorMessage: String?
    @State private var isDetectingSensitiveContent = false

    private let recognitionService = ImageRecognitionService()

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            Divider()

            CaptureEditorCanvas(
                source: source,
                model: model,
                onTextRequested: { point in
                    pendingTextPoint = point
                    textInput = ""
                }
            )
            .background(Color.black.opacity(0.82))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            bottomBar
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(L10n.editorTextTitle, isPresented: textAlertBinding) {
            TextField(L10n.editorTextPlaceholder, text: $textInput)
            Button(L10n.actionCancel, role: .cancel) {
                pendingTextPoint = nil
            }
            Button(L10n.editorTextAdd) {
                addPendingText()
            }
        }
        .alert(L10n.editorErrorTitle, isPresented: errorAlertBinding) {
            Button(L10n.actionOK) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var toolBar: some View {
        VStack(spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CaptureEditorTool.allCases) { tool in
                        Button {
                            model.selectedTool = tool
                        } label: {
                            Label(tool.displayName, systemImage: tool.symbol)
                                .labelStyle(.iconOnly)
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(model.selectedTool == tool ? .accentColor : nil)
                        .help(tool.displayName)
                    }

                    Divider().frame(height: 22)

                    Button {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .help(L10n.editorUndo)

                    Button {
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help(L10n.editorRedo)

                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.editorClear)

                    Button {
                        suggestRedactions()
                    } label: {
                        if isDetectingSensitiveContent {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDetectingSensitiveContent)
                    .help(L10n.editorSuggestRedactions)
                }
            }

            HStack(spacing: 12) {
                ColorPicker(
                    L10n.editorColor,
                    selection: Binding(
                        get: { Color(nsColor: model.color) },
                        set: { model.color = NSColor($0) }
                    ),
                    supportsOpacity: false
                )
                .frame(width: 90)

                Text(L10n.editorWidth)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Slider(value: $model.lineWidth, in: 2...24, step: 1)
                    .frame(width: 130)
                Text("\(Int(model.lineWidth))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 24)

                Spacer()

                Text(L10n.editorOutputSize)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                sizeField(
                    value: model.outputWidth,
                    onCommit: model.setOutputWidth
                )
                Text("×")
                    .foregroundStyle(.secondary)
                sizeField(
                    value: model.outputHeight,
                    onCommit: model.setOutputHeight
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        HStack {
            Text(L10n.editorHint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.actionCancel, action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button(L10n.editorFinish) {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var textAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingTextPoint != nil },
            set: { visible in
                if !visible {
                    pendingTextPoint = nil
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { visible in
                if !visible {
                    errorMessage = nil
                }
            }
        )
    }

    private func sizeField(value: Int, onCommit: @escaping (Int) -> Void) -> some View {
        TextField(
            "",
            text: Binding(
                get: { "\(value)" },
                set: { text in
                    if let number = Int(text) {
                        onCommit(number)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 72)
        .multilineTextAlignment(.trailing)
    }

    private func addPendingText() {
        guard let point = pendingTextPoint else { return }
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingTextPoint = nil
        guard !trimmed.isEmpty else { return }
        model.add(
            .text(
                origin: point,
                text: trimmed,
                color: CaptureEditorColor(model.color),
                fontSize: max(18, model.lineWidth * 5)
            )
        )
    }

    private func finish() {
        do {
            let output = try CaptureEditorRenderer.render(
                source: source,
                commands: model.commands,
                cropRect: model.cropRect,
                outputSize: CGSize(width: model.outputWidth, height: model.outputHeight)
            )
            onFinish(output)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func suggestRedactions() {
        guard !isDetectingSensitiveContent else { return }
        isDetectingSensitiveContent = true
        Task {
            do {
                let rects = try await recognitionService.sensitiveContentRects(in: source)
                await MainActor.run {
                    isDetectingSensitiveContent = false
                    if rects.isEmpty {
                        errorMessage = L10n.editorNoSensitiveContent
                    } else {
                        for rect in rects {
                            model.add(.mosaic(rect: rect))
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isDetectingSensitiveContent = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct CaptureEditorCanvas: NSViewRepresentable {
    let source: CGImage
    @ObservedObject var model: CaptureEditorModel
    let onTextRequested: (CGPoint) -> Void

    func makeNSView(context: Context) -> CaptureEditorCanvasNSView {
        CaptureEditorCanvasNSView(
            source: source,
            model: model,
            onTextRequested: onTextRequested
        )
    }

    func updateNSView(_ nsView: CaptureEditorCanvasNSView, context: Context) {
        nsView.model = model
        nsView.onTextRequested = onTextRequested
        nsView.needsDisplay = true
    }
}

@MainActor
private final class CaptureEditorCanvasNSView: NSView {
    let source: CGImage
    var model: CaptureEditorModel
    var onTextRequested: (CGPoint) -> Void

    private var dragStart: CGPoint?
    private var currentPoint: CGPoint?
    private var penPoints: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }

    init(
        source: CGImage,
        model: CaptureEditorModel,
        onTextRequested: @escaping (CGPoint) -> Void
    ) {
        self.source = source
        self.model = model
        self.onTextRequested = onTextRequested
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        bounds.fill()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let imageRect = fittedImageRect()
        let scale = imageRect.width / CGFloat(source.width)

        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: scale, y: scale)
        context.clip(to: CGRect(x: 0, y: 0, width: source.width, height: source.height))

        var commands = model.commands
        if let draft = draftCommand() {
            commands.append(draft)
        }
        CaptureEditorRenderer.drawPreview(
            source: source,
            commands: commands,
            cropRect: draftCropRect() ?? model.cropRect,
            in: context
        )
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = sourcePoint(for: event) else { return }
        window?.makeFirstResponder(self)

        switch model.selectedTool {
        case .text:
            onTextRequested(point)
        case .number:
            model.add(
                .number(
                    center: point,
                    value: model.nextNumber,
                    color: CaptureEditorColor(model.color),
                    radius: max(14, model.lineWidth * 3)
                )
            )
        default:
            dragStart = point
            currentPoint = point
            penPoints = [point]
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil, let point = sourcePoint(for: event) else { return }
        currentPoint = point
        if model.selectedTool == .pen {
            penPoints.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart,
              let end = sourcePoint(for: event)
        else { return }
        currentPoint = end

        if model.selectedTool == .crop {
            model.setCropRect(normalizedRect(from: start, to: end))
        } else if let command = draftCommand(), isMeaningful(command) {
            model.add(command)
        }

        dragStart = nil
        currentPoint = nil
        penPoints = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers == "z" {
            flags.contains(.shift) ? model.redo() : model.undo()
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    private func fittedImageRect() -> CGRect {
        let sourceSize = CGSize(width: source.width, height: source.height)
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func sourcePoint(for event: NSEvent) -> CGPoint? {
        let local = convert(event.locationInWindow, from: nil)
        let imageRect = fittedImageRect()
        guard imageRect.contains(local) else { return nil }
        let scale = imageRect.width / CGFloat(source.width)
        return CGPoint(
            x: (local.x - imageRect.minX) / scale,
            y: (local.y - imageRect.minY) / scale
        )
    }

    private func draftCommand() -> CaptureEditorCommand? {
        guard let start = dragStart, let end = currentPoint else { return nil }
        let color = CaptureEditorColor(model.color)
        let width = model.lineWidth
        let rect = normalizedRect(from: start, to: end)

        switch model.selectedTool {
        case .rectangle:
            return .rectangle(rect: rect, color: color, width: width)
        case .ellipse:
            return .ellipse(rect: rect, color: color, width: width)
        case .arrow:
            return .arrow(start: start, end: end, color: color, width: width)
        case .pen:
            return .pen(points: penPoints, color: color, width: width)
        case .highlight:
            return .highlight(rect: rect, color: CaptureEditorColor(.systemYellow))
        case .mosaic:
            return .mosaic(rect: rect)
        case .crop, .text, .number:
            return nil
        }
    }

    private func draftCropRect() -> CGRect? {
        guard model.selectedTool == .crop,
              let start = dragStart,
              let end = currentPoint
        else { return nil }
        return normalizedRect(from: start, to: end)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func isMeaningful(_ command: CaptureEditorCommand) -> Bool {
        switch command {
        case let .rectangle(rect, _, _),
             let .ellipse(rect, _, _),
             let .highlight(rect, _),
             let .mosaic(rect):
            return rect.width >= 2 && rect.height >= 2
        case let .arrow(start, end, _, _):
            return hypot(end.x - start.x, end.y - start.y) >= 2
        case let .pen(points, _, _):
            return points.count >= 2
        case .text, .number:
            return true
        }
    }
}
