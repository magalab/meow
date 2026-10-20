import AppKit
import Foundation
import MeowCapture

extension CaptureEditorTool {
    var displayName: String {
        switch self {
        case .crop: L10n.editorToolCrop
        case .rectangle: L10n.editorToolRectangle
        case .ellipse: L10n.editorToolEllipse
        case .arrow: L10n.editorToolArrow
        case .pen: L10n.editorToolPen
        case .text: L10n.editorToolText
        case .number: L10n.editorToolNumber
        case .highlight: L10n.editorToolHighlight
        case .mosaic: L10n.editorToolMosaic
        }
    }
}

extension CaptureEditorRenderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed: L10n.editorErrorContext
        case .imageCreationFailed: L10n.editorErrorImage
        }
    }
}

@MainActor
final class CaptureEditorModel: ObservableObject {
    @Published var selectedTool: CaptureEditorTool = .rectangle
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 5
    @Published var commands: [CaptureEditorCommand] = []
    @Published var cropRect: CGRect?
    @Published var outputWidth: Int
    @Published var outputHeight: Int
    @Published private(set) var nextNumber = 1

    let sourceSize: CGSize
    private var redoCommands: [CaptureEditorCommand] = []

    init(sourceSize: CGSize) {
        self.sourceSize = sourceSize
        outputWidth = Int(sourceSize.width)
        outputHeight = Int(sourceSize.height)
    }

    var canUndo: Bool { !commands.isEmpty }
    var canRedo: Bool { !redoCommands.isEmpty }

    func add(_ command: CaptureEditorCommand) {
        commands.append(command)
        redoCommands.removeAll()
        if case let .number(_, value, _, _) = command {
            nextNumber = max(nextNumber, value + 1)
        }
    }

    func undo() {
        guard let command = commands.popLast() else { return }
        redoCommands.append(command)
        recalculateNextNumber()
    }

    func redo() {
        guard let command = redoCommands.popLast() else { return }
        commands.append(command)
        recalculateNextNumber()
    }

    func clear() {
        commands.removeAll()
        redoCommands.removeAll()
        cropRect = nil
        nextNumber = 1
    }

    func setCropRect(_ rect: CGRect?) {
        guard let rect else {
            cropRect = nil
            outputWidth = Int(sourceSize.width)
            outputHeight = Int(sourceSize.height)
            return
        }
        let bounded = rect.standardized.intersection(CGRect(origin: .zero, size: sourceSize)).integral
        guard bounded.width >= 2, bounded.height >= 2 else { return }
        cropRect = bounded
        outputWidth = Int(bounded.width)
        outputHeight = Int(bounded.height)
    }

    func setOutputWidth(_ width: Int) {
        let source = cropRect?.size ?? sourceSize
        let bounded = min(max(width, 1), 16_384)
        outputWidth = bounded
        outputHeight = max(1, Int((CGFloat(bounded) * source.height / source.width).rounded()))
    }

    func setOutputHeight(_ height: Int) {
        let source = cropRect?.size ?? sourceSize
        let bounded = min(max(height, 1), 16_384)
        outputHeight = bounded
        outputWidth = max(1, Int((CGFloat(bounded) * source.width / source.height).rounded()))
    }

    private func recalculateNextNumber() {
        nextNumber = (commands.compactMap { command in
            if case let .number(_, value, _, _) = command {
                return value
            }
            return nil
        }.max() ?? 0) + 1
    }
}
