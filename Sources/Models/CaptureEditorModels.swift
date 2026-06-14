import AppKit
import Foundation

enum CaptureEditorTool: String, CaseIterable, Identifiable {
    case crop
    case rectangle
    case ellipse
    case arrow
    case pen
    case text
    case number
    case highlight
    case mosaic

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .crop: return "crop"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .number: return "1.circle"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }

    var displayName: String {
        switch self {
        case .crop: return L10n.editorToolCrop
        case .rectangle: return L10n.editorToolRectangle
        case .ellipse: return L10n.editorToolEllipse
        case .arrow: return L10n.editorToolArrow
        case .pen: return L10n.editorToolPen
        case .text: return L10n.editorToolText
        case .number: return L10n.editorToolNumber
        case .highlight: return L10n.editorToolHighlight
        case .mosaic: return L10n.editorToolMosaic
        }
    }
}
struct CaptureEditorColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(
            deviceRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    static let red = CaptureEditorColor(.systemRed)
    static let yellow = CaptureEditorColor(.systemYellow)
}

enum CaptureEditorCommand: Equatable, Sendable {
    case rectangle(rect: CGRect, color: CaptureEditorColor, width: CGFloat)
    case ellipse(rect: CGRect, color: CaptureEditorColor, width: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: CaptureEditorColor, width: CGFloat)
    case pen(points: [CGPoint], color: CaptureEditorColor, width: CGFloat)
    case text(origin: CGPoint, text: String, color: CaptureEditorColor, fontSize: CGFloat)
    case number(center: CGPoint, value: Int, color: CaptureEditorColor, radius: CGFloat)
    case highlight(rect: CGRect, color: CaptureEditorColor)
    case mosaic(rect: CGRect)
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
