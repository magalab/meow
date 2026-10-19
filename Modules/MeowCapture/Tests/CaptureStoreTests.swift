import Foundation
import MeowCapture
import Testing

@MainActor
@Test("Capture store keeps the existing history file format")
func captureStoreHistoryCompatibility() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeowCaptureStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let id = try #require(UUID(uuidString: "D75DCC64-01A6-431A-852A-F8F0E610E13F"))
    let imageURL = directory.appendingPathComponent("capture.png")
    let thumbnailURL = directory.appendingPathComponent("capture-thumb.png")
    try Data([1, 2, 3]).write(to: imageURL)
    try Data([4, 5, 6]).write(to: thumbnailURL)
    let legacyJSON = Data(
        """
        [{
          "id": "\(id.uuidString)",
          "kind": "region",
          "createdAt": 790000000,
          "imageURL": "\(imageURL.absoluteString)",
          "thumbnailURL": "\(thumbnailURL.absoluteString)",
          "width": 1280,
          "height": 720
        }]
        """.utf8
    )
    try legacyJSON.write(to: directory.appendingPathComponent("index.json"))

    let store = CaptureStore(capturesDirectory: directory)
    #expect(store.artifacts.count == 1)
    #expect(store.artifacts.first?.id == id)
    #expect(store.artifacts.first?.ocrText == nil)

    store.applyRetention(historyLimit: 100, retentionDays: 0, maxStorageMB: 0)
    let rewritten = try Data(contentsOf: directory.appendingPathComponent("index.json"))
    let records = try #require(JSONSerialization.jsonObject(with: rewritten) as? [[String: Any]])
    #expect(Set(try #require(records.first).keys) == [
        "id", "kind", "createdAt", "imageURL", "thumbnailURL", "width", "height",
    ])
}

@Test("Capture image formats retain their persisted raw values")
func captureImageFormatRawValues() {
    #expect(ScreenshotImageFormat.png.rawValue == "png")
    #expect(ScreenshotImageFormat.jpeg.rawValue == "jpeg")
    #expect(ScreenshotImageFormat.png.fileExtension == "png")
    #expect(ScreenshotImageFormat.jpeg.fileExtension == "jpg")
}
