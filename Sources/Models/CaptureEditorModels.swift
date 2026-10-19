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
