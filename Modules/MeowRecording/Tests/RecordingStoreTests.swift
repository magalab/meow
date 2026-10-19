import Foundation
import MeowRecording
import Testing

@Test("Recording settings preserve legacy defaults and stored values")
func recordingSettingsDefaultsAndRoundTrip() throws {
    let decoded = try JSONDecoder().decode(
        RecordingSettings.self,
        from: Data(#"{"enabled":true,"frameRate":30}"#.utf8)
    )
    #expect(decoded.enabled)
    #expect(decoded.frameRate == 30)
    #expect(decoded.videoFormat == .mp4)
    #expect(decoded.audioMode == .system)

    let encoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(RecordingSettings.self, from: encoded)
    #expect(roundTripped == decoded)
}

@MainActor
@Test("Recording store retains the existing history schema")
func recordingStoreHistorySchemaCompatibility() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeowRecordingStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let id = try #require(UUID(uuidString: "D75DCC64-01A6-431A-852A-F8F0E610E13F"))
    let fileURL = directory.appendingPathComponent("legacy.mp4")
    try Data([1, 2, 3]).write(to: fileURL)
    let legacyMetadata = Data(
        """
        [{
          "id": "\(id.uuidString)",
          "source": "display",
          "createdAt": 790000000,
          "duration": 42.5,
          "fileURL": "\(fileURL.absoluteString)",
          "width": 1920,
          "height": 1080,
          "fileSize": 3,
          "hasSystemAudio": true,
          "hasMicrophoneAudio": false
        }]
        """.utf8
    )
    try legacyMetadata.write(to: directory.appendingPathComponent("index.json"))

    let store = RecordingStore(storageDirectory: directory)
    let artifact = try #require(store.artifacts.first)
    #expect(store.artifacts.count == 1)
    #expect(artifact.id == id)
    #expect(artifact.thumbnailURL == nil)
    #expect(artifact.videoCodec == nil)

    let rewritten = try Data(contentsOf: directory.appendingPathComponent("index.json"))
    let records = try #require(JSONSerialization.jsonObject(with: rewritten) as? [[String: Any]])
    #expect(Set(try #require(records.first).keys) == [
        "id", "source", "createdAt", "duration", "fileURL", "width", "height", "fileSize",
        "hasSystemAudio", "hasMicrophoneAudio",
    ])
}
