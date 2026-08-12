import CoreGraphics
import Foundation

enum ScrollingCaptureProcessOutcome: Sendable {
    case appended(ScrollingCaptureProgress)
    case waiting(ScrollingCaptureProgress)
    case paused(ScrollingCaptureProgress)
    case reachedLimit(ScrollingCaptureStopReason, ScrollingCaptureProgress)
}

actor ScrollingCaptureProcessor {
    static let safeFinalImageMaximumPixels = 20_000_000

    private let settings: ScrollingCaptureSettings
    private let stitcher: ScrollingCaptureStitcher
    private var referenceFrame: CGImage
    private var receivedFrameCount = 1
    private var appendedStripCount = 0
    private var consecutiveFailures = 0
    private var consecutiveStableFrames = 0
    private var frozenHeaderCandidates: [Int] = []
    private var confirmedFrozenHeaderHeight = 0
    private var latestConfidence = 0.0

    init(firstFrame: CGImage, settings: ScrollingCaptureSettings) {
        self.settings = settings
        referenceFrame = firstFrame
        stitcher = ScrollingCaptureStitcher(
            firstFrame: firstFrame,
            maximumHeight: settings.maximumHeightPixels,
            maximumPixels: settings.maximumTotalPixels
        )
    }

    func initialProgress(isAutoScrolling: Bool) -> ScrollingCaptureProgress {
        progress(state: .capturing, isAutoScrolling: isAutoScrolling)
    }

    func process(
        _ frame: CGImage,
        isAutoScrolling: Bool
    ) -> ScrollingCaptureProcessOutcome {
        receivedFrameCount += 1
        if ScrollingCaptureMatcher.framesAreStable(referenceFrame, frame) {
            consecutiveStableFrames += 1
            consecutiveFailures = 0
            latestConfidence = 1
            let currentProgress = progress(
                state: isAutoScrolling && consecutiveStableFrames >= 3 ? .finishing : .capturing,
                isAutoScrolling: isAutoScrolling
            )
            if isAutoScrolling, consecutiveStableFrames >= 3 {
                return .reachedLimit(.completed, currentProgress)
            }
            return .waiting(currentProgress)
        }
        consecutiveStableFrames = 0
        guard let match = ScrollingCaptureMatcher.match(
            previous: referenceFrame,
            current: frame,
            frozenHeaderHeight: confirmedFrozenHeaderHeight
        ) else {
            consecutiveFailures += 1
            latestConfidence = 0
            let state: ScrollingCaptureState = consecutiveFailures >= 8 ? .paused : .capturing
            let currentProgress = progress(state: state, isAutoScrolling: isAutoScrolling)
            return consecutiveFailures >= 8 ? .paused(currentProgress) : .waiting(currentProgress)
        }
        consecutiveFailures = 0

        let minimumUsefulShift = max(4, frame.height / 10)
        guard match.verticalOffset >= minimumUsefulShift else {
            latestConfidence = match.confidence
            return .waiting(progress(state: .capturing, isAutoScrolling: isAutoScrolling))
        }

        if settings.automaticallyDetectFrozenHeader, confirmedFrozenHeaderHeight == 0 {
            recordFrozenHeaderCandidate(ScrollingCaptureMatcher.frozenHeaderHeight(
                previous: referenceFrame,
                current: frame
            ))
        }

        switch stitcher.appendBottomRows(from: frame, count: match.verticalOffset) {
        case .appended:
            referenceFrame = frame
            appendedStripCount += 1
            consecutiveFailures = 0
            consecutiveStableFrames = 0
            latestConfidence = match.confidence
            return .appended(progress(state: .capturing, isAutoScrolling: isAutoScrolling))
        case .maximumHeight:
            return .reachedLimit(
                .maximumHeight,
                progress(state: .finishing, isAutoScrolling: false)
            )
        case .maximumPixels:
            return .reachedLimit(
                .maximumPixels,
                progress(state: .finishing, isAutoScrolling: false)
            )
        case .invalidFrame:
            consecutiveFailures += 1
            let currentProgress = progress(state: .paused, isAutoScrolling: false)
            return .paused(currentProgress)
        }
    }

    func progress(state: ScrollingCaptureState, isAutoScrolling: Bool) -> ScrollingCaptureProgress {
        ScrollingCaptureProgress(
            receivedFrameCount: receivedFrameCount,
            stitchedStripCount: appendedStripCount,
            pixelSize: stitcher.pixelSize,
            latestMatchConfidence: latestConfidence,
            isAutoScrolling: isAutoScrolling,
            state: state
        )
    }

    func makePreview() -> CGImage? {
        stitcher.makePreview()
    }

    func makeFinalImage(
        maximumPixels: Int = ScrollingCaptureProcessor.safeFinalImageMaximumPixels
    ) -> ScrollingCaptureFinalImage? {
        let pixelSize = stitcher.pixelSize
        let pixelCount = Double(pixelSize.width) * Double(pixelSize.height)
        if maximumPixels > 0, pixelCount > Double(maximumPixels) {
            guard let image = stitcher.makeReducedImage(maximumPixels: maximumPixels) else {
                return nil
            }
            return ScrollingCaptureFinalImage(image: image, isReduced: true)
        }
        if let image = stitcher.makeImage() {
            return ScrollingCaptureFinalImage(image: image, isReduced: false)
        }
        guard let image = stitcher.makeReducedImage(maximumPixels: maximumPixels) else {
            return nil
        }
        return ScrollingCaptureFinalImage(image: image, isReduced: true)
    }

    func resumeAfterPause() {
        consecutiveFailures = 0
        consecutiveStableFrames = 0
    }

    private func recordFrozenHeaderCandidate(_ candidate: Int) {
        frozenHeaderCandidates.append(candidate)
        guard frozenHeaderCandidates.count >= 2 else { return }
        let recent = Array(frozenHeaderCandidates.suffix(2))
        guard let minimum = recent.min(), let maximum = recent.max() else { return }
        if minimum >= 10, maximum - minimum <= 6 {
            confirmedFrozenHeaderHeight = minimum
        } else if frozenHeaderCandidates.count >= 3 {
            confirmedFrozenHeaderHeight = 0
        }
    }
}
