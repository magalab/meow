import AppKit
import Combine
import Foundation

@MainActor
public final class CaptureEditorModel: ObservableObject {
    @Published public var selectedTool: CaptureEditorTool = .rectangle
    @Published public var color: NSColor = .systemRed
    @Published public var lineWidth: CGFloat = 5
    @Published public var commands: [CaptureEditorCommand] = []
    @Published public var cropRect: CGRect?
    @Published public var outputWidth: Int
    @Published public var outputHeight: Int
    @Published public private(set) var nextNumber = 1

    public let sourceSize: CGSize
    private var redoCommands: [CaptureEditorCommand] = []

    public init(sourceSize: CGSize) {
        self.sourceSize = sourceSize
        outputWidth = Int(sourceSize.width)
        outputHeight = Int(sourceSize.height)
    }

    public var canUndo: Bool { !commands.isEmpty }
    public var canRedo: Bool { !redoCommands.isEmpty }

    public func add(_ command: CaptureEditorCommand) {
        commands.append(command)
        redoCommands.removeAll()
        if case let .number(_, value, _, _) = command {
            nextNumber = max(nextNumber, value + 1)
        }
    }

    public func undo() {
        guard let command = commands.popLast() else { return }
        redoCommands.append(command)
        recalculateNextNumber()
    }

    public func redo() {
        guard let command = redoCommands.popLast() else { return }
        commands.append(command)
        recalculateNextNumber()
    }

    public func clear() {
        commands.removeAll()
        redoCommands.removeAll()
        cropRect = nil
        nextNumber = 1
    }

    public func setCropRect(_ rect: CGRect?) {
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

    public func setOutputWidth(_ width: Int) {
        let source = cropRect?.size ?? sourceSize
        let bounded = min(max(width, 1), 16_384)
        outputWidth = bounded
        outputHeight = max(1, Int((CGFloat(bounded) * source.height / source.width).rounded()))
    }

    public func setOutputHeight(_ height: Int) {
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
