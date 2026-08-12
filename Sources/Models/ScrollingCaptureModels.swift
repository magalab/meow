import CoreGraphics
import Foundation

enum ScrollingCaptureSpeed: Int, Codable, CaseIterable, Identifiable, Sendable {
    case slow = 1
    case medium = 2
    case fast = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .slow: return L10n.scrollingCaptureSpeedSlow
        case .medium: return L10n.scrollingCaptureSpeedMedium
        case .fast: return L10n.scrollingCaptureSpeedFast
        }
    }

    var scrollLines: Int32 {
        switch self {
        case .slow: return 2
        case .medium: return 4
        case .fast: return 7
        }
    }
}

struct ScrollingCaptureSettings: Codable, Equatable, Sendable {
    var maximumHeightPixels: Int
    var maximumTotalPixels: Int
    var manualCaptureInterval: TimeInterval
    var settlementDelay: TimeInterval
    var automaticallyDetectFrozenHeader: Bool
    var autoScrollEnabled: Bool
    var autoScrollSpeed: ScrollingCaptureSpeed

    static let `default` = ScrollingCaptureSettings(
        maximumHeightPixels: 30_000,
        maximumTotalPixels: 80_000_000,
        manualCaptureInterval: 0.15,
        settlementDelay: 0.25,
        automaticallyDetectFrozenHeader: true,
        autoScrollEnabled: false,
        autoScrollSpeed: .medium
    )

    private enum CodingKeys: String, CodingKey {
        case maximumHeightPixels
        case maximumTotalPixels
        case manualCaptureInterval
        case settlementDelay
        case automaticallyDetectFrozenHeader
        case autoScrollEnabled
        case autoScrollSpeed
    }

    init(
        maximumHeightPixels: Int,
        maximumTotalPixels: Int,
        manualCaptureInterval: TimeInterval,
        settlementDelay: TimeInterval,
        automaticallyDetectFrozenHeader: Bool,
        autoScrollEnabled: Bool,
        autoScrollSpeed: ScrollingCaptureSpeed
    ) {
        self.maximumHeightPixels = maximumHeightPixels
        self.maximumTotalPixels = maximumTotalPixels
        self.manualCaptureInterval = manualCaptureInterval
        self.settlementDelay = settlementDelay
        self.automaticallyDetectFrozenHeader = automaticallyDetectFrozenHeader
        self.autoScrollEnabled = autoScrollEnabled
        self.autoScrollSpeed = autoScrollSpeed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maximumHeightPixels = max(1_000, try container.decodeIfPresent(
            Int.self,
            forKey: .maximumHeightPixels
        ) ?? Self.default.maximumHeightPixels)
        maximumTotalPixels = max(1_000_000, try container.decodeIfPresent(
            Int.self,
            forKey: .maximumTotalPixels
        ) ?? Self.default.maximumTotalPixels)
        manualCaptureInterval = min(1, max(0.05, try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .manualCaptureInterval
        ) ?? Self.default.manualCaptureInterval))
        settlementDelay = min(2, max(0.05, try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .settlementDelay
        ) ?? Self.default.settlementDelay))
        automaticallyDetectFrozenHeader = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyDetectFrozenHeader
        ) ?? Self.default.automaticallyDetectFrozenHeader
        autoScrollEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoScrollEnabled
        ) ?? Self.default.autoScrollEnabled
        autoScrollSpeed = try container.decodeIfPresent(
            ScrollingCaptureSpeed.self,
            forKey: .autoScrollSpeed
        ) ?? Self.default.autoScrollSpeed
    }
}

enum ScrollingCaptureState: Equatable, Sendable {
    case idle
    case preparing
    case capturing
    case paused
    case finishing
    case failed(String)
}

struct ScrollingCaptureProgress: Equatable, Sendable {
    var receivedFrameCount: Int
    var stitchedStripCount: Int
    var pixelSize: CGSize
    var latestMatchConfidence: Double
    var isAutoScrolling: Bool
    var state: ScrollingCaptureState

    static let idle = ScrollingCaptureProgress(
        receivedFrameCount: 0,
        stitchedStripCount: 0,
        pixelSize: .zero,
        latestMatchConfidence: 0,
        isAutoScrolling: false,
        state: .idle
    )
}

enum ScrollingCaptureStopReason: Equatable, Sendable {
    case completed
    case maximumHeight
    case maximumPixels
    case consecutiveMatchFailures
}

struct ScrollingCaptureFinalImage: @unchecked Sendable {
    let image: CGImage
    let isReduced: Bool
}

enum ScrollingCaptureSessionResult {
    case completed(ScrollingCaptureFinalImage)
    case cancelled
    case failed(any Error)
}

enum ScrollingCaptureError: LocalizedError {
    case finalCompositionFailed

    var errorDescription: String? {
        switch self {
        case .finalCompositionFailed:
            return L10n.scrollingCaptureErrorFinalComposition
        }
    }
}
