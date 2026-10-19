import CoreGraphics
import Foundation

public struct ScrollingCaptureProcessorConfiguration: Equatable, Sendable {
    public let maximumHeightPixels: Int
    public let maximumTotalPixels: Int
    public let automaticallyDetectFrozenHeader: Bool

    public init(
        maximumHeightPixels: Int,
        maximumTotalPixels: Int,
        automaticallyDetectFrozenHeader: Bool
    ) {
        self.maximumHeightPixels = maximumHeightPixels
        self.maximumTotalPixels = maximumTotalPixels
        self.automaticallyDetectFrozenHeader = automaticallyDetectFrozenHeader
    }
}

public enum ScrollingCaptureState: Equatable, Sendable {
    case idle
    case preparing
    case capturing
    case paused
    case finishing
    case failed(String)
}

public struct ScrollingCaptureProgress: Equatable, Sendable {
    public var receivedFrameCount: Int
    public var stitchedStripCount: Int
    public var pixelSize: CGSize
    public var latestMatchConfidence: Double
    public var isAutoScrolling: Bool
    public var state: ScrollingCaptureState

    public init(
        receivedFrameCount: Int,
        stitchedStripCount: Int,
        pixelSize: CGSize,
        latestMatchConfidence: Double,
        isAutoScrolling: Bool,
        state: ScrollingCaptureState
    ) {
        self.receivedFrameCount = receivedFrameCount
        self.stitchedStripCount = stitchedStripCount
        self.pixelSize = pixelSize
        self.latestMatchConfidence = latestMatchConfidence
        self.isAutoScrolling = isAutoScrolling
        self.state = state
    }

    public static let idle = Self(
        receivedFrameCount: 0,
        stitchedStripCount: 0,
        pixelSize: .zero,
        latestMatchConfidence: 0,
        isAutoScrolling: false,
        state: .idle
    )
}

public enum ScrollingCaptureStopReason: Equatable, Sendable {
    case completed
    case maximumHeight
    case maximumPixels
    case consecutiveMatchFailures
}

public struct ScrollingCaptureFinalImage: @unchecked Sendable {
    public let image: CGImage
    public let isReduced: Bool

    public init(image: CGImage, isReduced: Bool) {
        self.image = image
        self.isReduced = isReduced
    }
}

public enum ScrollingCaptureProcessOutcome: Sendable {
    case appended(ScrollingCaptureProgress)
    case waiting(ScrollingCaptureProgress)
    case paused(ScrollingCaptureProgress)
    case reachedLimit(ScrollingCaptureStopReason, ScrollingCaptureProgress)
}
