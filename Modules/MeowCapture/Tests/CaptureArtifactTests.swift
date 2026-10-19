import Foundation
import MeowCapture
import Testing

@Test("Capture artifacts retain their persisted fields and decode older records")
func captureArtifactPersistenceCompatibility() throws {
    let artifact = CaptureArtifact(
        id: try #require(UUID(uuidString: "27F2D468-CE09-4BDE-A3DC-98936ED4A4BD")),
        kind: .scrolling,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        imageURL: URL(fileURLWithPath: "/tmp/capture.png"),
        thumbnailURL: URL(fileURLWithPath: "/tmp/capture-thumb.png"),
        width: 2_000,
        height: 5_000,
        ocrText: "recognized text"
    )
    let encoder = JSONEncoder()
    let encoded = try encoder.encode(artifact)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(Set(object.keys) == [
        "id", "kind", "createdAt", "imageURL", "thumbnailURL", "width", "height", "ocrText",
    ])

    var legacyRecord = object
    legacyRecord.removeValue(forKey: "ocrText")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyRecord)
    let decoded = try JSONDecoder().decode(CaptureArtifact.self, from: legacyData)
    #expect(decoded.id == artifact.id)
    #expect(decoded.kind == artifact.kind)
    #expect(decoded.createdAt == artifact.createdAt)
    #expect(decoded.imageURL == artifact.imageURL)
    #expect(decoded.thumbnailURL == artifact.thumbnailURL)
    #expect(decoded.width == artifact.width)
    #expect(decoded.height == artifact.height)
    #expect(decoded.ocrText == nil)
}

@Test("Capture artifact size checks remain bounded and overflow safe")
func captureArtifactSizeLimits() {
    let automaticOCR = CaptureArtifact(
        id: UUID(), kind: .region, createdAt: .now,
        imageURL: URL(fileURLWithPath: "/tmp/a"),
        thumbnailURL: URL(fileURLWithPath: "/tmp/b"),
        width: 4_000, height: 5_000
    )
    let largerImage = CaptureArtifact(
        id: UUID(), kind: .region, createdAt: .now,
        imageURL: URL(fileURLWithPath: "/tmp/a"),
        thumbnailURL: URL(fileURLWithPath: "/tmp/b"),
        width: 5_000, height: 5_000
    )
    let invalidSize = CaptureArtifact(
        id: UUID(), kind: .region, createdAt: .now,
        imageURL: URL(fileURLWithPath: "/tmp/a"),
        thumbnailURL: URL(fileURLWithPath: "/tmp/b"),
        width: -1, height: 5
    )

    #expect(automaticOCR.supportsAutomaticOCR)
    #expect(!largerImage.supportsAutomaticOCR)
    #expect(largerImage.supportsFullResolutionEditing)
    #expect(invalidSize.pixelCount == 0)
}
