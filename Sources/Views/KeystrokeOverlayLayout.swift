import Foundation

enum KeystrokeOverlayLayout {
    static func size(style: KeystrokeOverlayStyle, historyCount: KeystrokeHistoryCount) -> CGSize {
        switch style {
        case .compact:
            return CGSize(width: compactWidth(for: historyCount), height: 46)
        case .prominent:
            return CGSize(width: prominentWidth(for: historyCount), height: 64)
        }
    }

    private static func compactWidth(for historyCount: KeystrokeHistoryCount) -> CGFloat {
        switch historyCount {
        case .one: return 168
        case .two: return 210
        case .three: return 240
        }
    }

    private static func prominentWidth(for historyCount: KeystrokeHistoryCount) -> CGFloat {
        switch historyCount {
        case .one: return 240
        case .two: return 310
        case .three: return 360
        }
    }
}
