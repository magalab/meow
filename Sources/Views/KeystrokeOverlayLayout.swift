import Foundation

enum KeystrokeOverlayLayout {
    static func size(style: KeystrokeOverlayStyle, historyCount: KeystrokeHistoryCount) -> CGSize {
        switch style {
        case .compact:
            return CGSize(width: compactWidth(for: historyCount), height: 40)
        case .prominent:
            return CGSize(width: prominentWidth(for: historyCount), height: 56)
        }
    }

    private static func compactWidth(for historyCount: KeystrokeHistoryCount) -> CGFloat {
        switch historyCount {
        case .one: return 148
        case .two: return 184
        case .three: return 212
        }
    }

    private static func prominentWidth(for historyCount: KeystrokeHistoryCount) -> CGFloat {
        switch historyCount {
        case .one: return 210
        case .two: return 272
        case .three: return 316
        }
    }
}
