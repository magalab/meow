import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Testing
import MeowRecording

@Test(
    "Recorded click ring is composited into a video sample",
    arguments: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_ARGB2101010LEPacked,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]
)
func recordedMouseClickRingIsInVideoSample(pixelFormat: OSType) throws {
    let captureRect = CGRect(x: 100, y: 200, width: 128, height: 128)
    #expect(RecordingMouseClickCompositor.pixelCenter(
        for: CGPoint(x: 164, y: 264),
        captureRect: captureRect,
        imageSize: CGSize(width: 128, height: 128)
    ) == CGPoint(x: 64, y: 64))

    var pixelBuffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(
        kCFAllocatorDefault,
        128,
        128,
        pixelFormat,
        nil,
        &pixelBuffer
    ) == kCVReturnSuccess)
    let sourceBuffer = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(sourceBuffer, [])
    if CVPixelBufferGetPlaneCount(sourceBuffer) == 0 {
        memset(CVPixelBufferGetBaseAddress(sourceBuffer), 0, CVPixelBufferGetDataSize(sourceBuffer))
    } else {
        for plane in 0..<CVPixelBufferGetPlaneCount(sourceBuffer) {
            memset(
                CVPixelBufferGetBaseAddressOfPlane(sourceBuffer, plane),
                plane == 0 ? 0 : 128,
                CVPixelBufferGetBytesPerRowOfPlane(sourceBuffer, plane)
                    * CVPixelBufferGetHeightOfPlane(sourceBuffer, plane)
            )
        }
    }
    CVPixelBufferUnlockBaseAddress(sourceBuffer, [])

    var format: CMVideoFormatDescription?
    #expect(CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: sourceBuffer,
        formatDescriptionOut: &format
    ) == noErr)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(value: 1, timescale: 1),
        decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    #expect(CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: sourceBuffer,
        formatDescription: try #require(format),
        sampleTiming: &timing,
        sampleBufferOut: &sample
    ) == noErr)

    let compositor = RecordingMouseClickCompositor(
        captureRect: captureRect,
        enabled: true,
        color: RecordingHighlightColor(red: 0.85, green: 0.47, blue: 0.24)
    )
    compositor.recordClick(at: CGPoint(x: 164, y: 264))
    let output = compositor.composite(try #require(sample))
    let result = try #require(output.imageBuffer)
    #expect(result !== sourceBuffer)
    CVPixelBufferLockBaseAddress(result, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(result, .readOnly) }
    if CVPixelBufferGetPlaneCount(result) > 0 {
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(result, 0))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let count = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
            * CVPixelBufferGetHeightOfPlane(result, 0)
        #expect((0..<count).contains { bytes[$0] != 0 })
    } else {
        let base = try #require(CVPixelBufferGetBaseAddress(result))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        #expect((0..<CVPixelBufferGetDataSize(result)).contains { bytes[$0] != 0 })
    }
    if pixelFormat == kCVPixelFormatType_32BGRA {
        let base = try #require(CVPixelBufferGetBaseAddress(result))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let ringRow = 64 * CVPixelBufferGetBytesPerRow(result)
        #expect((75...80).contains { x in
            let pixel = ringRow + x * 4
            return bytes[pixel] != 0 || bytes[pixel + 1] != 0 || bytes[pixel + 2] != 0
        })
    }
    compositor.apply(enabled: false, color: RecordingHighlightColor(red: 0.85, green: 0.47, blue: 0.24))
    #expect(compositor.composite(try #require(sample)) === sample)
}

@Test(
    "Magnifier appears in encoded video samples and clears when closed",
    arguments: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_ARGB2101010LEPacked,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]
)
func recordedMagnifierIsInVideoSample(pixelFormat: OSType) throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, pixelFormat, nil, &buffer) == kCVReturnSuccess)
    let source = try #require(buffer)
    CVPixelBufferLockBaseAddress(source, [])
    if CVPixelBufferGetPlaneCount(source) == 0 {
        memset(CVPixelBufferGetBaseAddress(source), 0, CVPixelBufferGetDataSize(source))
        if pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked {
            let row = try #require(CVPixelBufferGetBaseAddress(source))
                .advanced(by: 32 * CVPixelBufferGetBytesPerRow(source))
                .assumingMemoryBound(to: UInt32.self)
            row[32] = 0xFFFFFFFF
        }
    } else {
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            memset(CVPixelBufferGetBaseAddressOfPlane(source, plane), plane == 0 ? 0 : 128,
                   CVPixelBufferGetBytesPerRowOfPlane(source, plane) * CVPixelBufferGetHeightOfPlane(source, plane))
        }
    }
    CVPixelBufferUnlockBaseAddress(source, [])
    var format: CMVideoFormatDescription?
    #expect(CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: source, formatDescriptionOut: &format
    ) == noErr)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                    presentationTimeStamp: CMTime(value: 1, timescale: 1),
                                    decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    #expect(CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: source,
        formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample
    ) == noErr)
    let context = try #require(CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    ))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let compositor = RecordingMagnifierCompositor(captureRect: CGRect(x: 0, y: 0, width: 64, height: 64))
    compositor.setImage(context.makeImage(), frame: CGRect(x: 20, y: 20, width: 16, height: 16))
    let output = compositor.composite(try #require(sample))
    let result = try #require(output.imageBuffer)
    #expect(result !== source)
    CVPixelBufferLockBaseAddress(result, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(result, 0)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
        #expect(bytes[32 * stride + 28] > 0)
        #expect(bytes[8 * stride + 8] == 0)
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(result)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(result)
        #expect((0..<4).contains { bytes[32 * stride + 28 * 4 + $0] != 0 })
        #expect((0..<4).allSatisfy { bytes[8 * stride + 8 * 4 + $0] == 0 })
        if pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked {
            let row = try #require(CVPixelBufferGetBaseAddress(result))
                .advanced(by: 32 * stride)
                .assumingMemoryBound(to: UInt32.self)
            // An opaque overlay must replace the old all-ones pixel rather
            // than OR its new channels into the old channel bits.
            #expect(row[32] != 0xFFFFFFFF)
            #expect(row[32] & 0x3FF == 0)
            #expect((row[32] >> 10) & 0x3FF < 512)
        }
    }
    CVPixelBufferUnlockBaseAddress(result, .readOnly)
    compositor.setFrame(CGRect(x: 40, y: 20, width: 16, height: 16))
    let movedSample = compositor.composite(try #require(sample))
    let moved = try #require(movedSample.imageBuffer)
    CVPixelBufferLockBaseAddress(moved, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(moved, 0)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(moved, 0)
        #expect(bytes[32 * stride + 28] == 0)
        #expect(bytes[32 * stride + 48] > 0)
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(moved)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(moved)
        #expect((0..<4).allSatisfy { bytes[32 * stride + 28 * 4 + $0] == 0 })
        #expect((0..<4).contains { bytes[32 * stride + 48 * 4 + $0] != 0 })
    }
    CVPixelBufferUnlockBaseAddress(moved, .readOnly)
    compositor.setImage(nil, frame: .zero)
    #expect(compositor.composite(try #require(sample)) === sample)
    compositor.setSnapshot(
        context.makeImage(), frame: CGRect(x: 8, y: 8, width: 48, height: 48),
        marker: CGPoint(x: 0.5, y: 0.5), zoom: 2, circular: false
    )
    #expect(compositor.composite(try #require(sample)).imageBuffer !== source)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    compositor.setImage(context.makeImage(), frame: CGRect(x: 20, y: 20, width: 16, height: 16))
    let orientedSample = compositor.composite(try #require(sample))
    let oriented = try #require(orientedSample.imageBuffer)
    CVPixelBufferLockBaseAddress(oriented, .readOnly)
    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(oriented, 0))
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(oriented, 0)
        #expect(bytes[42 * stride + 28] > bytes[30 * stride + 28])
    } else {
        let bytes = try #require(CVPixelBufferGetBaseAddress(oriented))
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(oriented)
        #expect(bytes[42 * stride + 28 * 4] > bytes[30 * stride + 28 * 4])
    }
    CVPixelBufferUnlockBaseAddress(oriented, .readOnly)
}
