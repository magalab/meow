import AppKit
import Foundation

public enum CaptureEditorTool: String, CaseIterable, Identifiable, Sendable {
    case crop
    case rectangle
    case ellipse
    case arrow
    case pen
    case text
    case number
    case highlight
    case mosaic

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .crop: "crop"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .number: "1.circle"
        case .highlight: "highlighter"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
}

public struct CaptureEditorColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    public var nsColor: NSColor {
        NSColor(
            deviceRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    public static let red = CaptureEditorColor(.systemRed)
    public static let yellow = CaptureEditorColor(.systemYellow)
}

public enum CaptureEditorCommand: Equatable, Sendable {
    case rectangle(rect: CGRect, color: CaptureEditorColor, width: CGFloat)
    case ellipse(rect: CGRect, color: CaptureEditorColor, width: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: CaptureEditorColor, width: CGFloat)
    case pen(points: [CGPoint], color: CaptureEditorColor, width: CGFloat)
    case text(origin: CGPoint, text: String, color: CaptureEditorColor, fontSize: CGFloat)
    case number(center: CGPoint, value: Int, color: CaptureEditorColor, radius: CGFloat)
    case highlight(rect: CGRect, color: CaptureEditorColor)
    case mosaic(rect: CGRect)
}
