import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("Recording settings decode missing fields with current defaults")
func recordingSettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(
        RecordingSettings.self,
        from: Data(#"{"enabled":true,"frameRate":30}"#.utf8)
    )
    #expect(settings.enabled)
    #expect(settings.frameRate == 30)
    #expect(settings.videoFormat == .mp4)
    #expect(settings.videoCodec == .h264)
    #expect(settings.audioMode == .system)
    #expect(settings.showFloatingControls)
    #expect(settings.cameraOverlayShape == .rounded)
}

@Test("Recording settings normalize HDR, alpha, and mobile output constraints")
func recordingSettingsNormalization() {
    var alpha = RecordingSettings.default
    alpha.videoFormat = .mp4
    alpha.videoCodec = .hevcWithAlpha
    alpha.recordHDR = true
    let normalizedAlpha = alpha.normalized()
    #expect(normalizedAlpha.videoFormat == .mov)
    #expect(normalizedAlpha.videoCodec == .hevcWithAlpha)
    #expect(!normalizedAlpha.recordHDR)

    var transparent = RecordingSettings.default
    transparent.backgroundStyle = .transparent
    let normalizedTransparent = transparent.normalized()
    #expect(normalizedTransparent.videoFormat == .mov)
    #expect(normalizedTransparent.videoCodec == .hevcWithAlpha)

    var hdr = RecordingSettings.default
    hdr.videoCodec = .h264
    hdr.videoFormat = .mp4
    hdr.recordHDR = true
    let normalizedHDR = hdr.normalized()
    #expect(normalizedHDR.videoFormat == .mov)
    #expect(normalizedHDR.videoCodec == .hevc)

    let mobile = hdr.normalized(for: .mobileDevice)
    #expect(mobile.videoFormat == .mov)
    #expect(mobile.videoCodec == .h264)
    #expect(mobile.audioMode == .none)
    #expect(!mobile.recordHDR)

    var exclusions = RecordingSettings.default
    exclusions.excludedApplicationBundleIDs = [
        " COM.EXAMPLE.Secret ",
        "com.example.secret",
        "",
    ]
    #expect(exclusions.normalized().excludedApplicationBundleIDs == ["com.example.secret"])
}

@Test("Mobile recordings always use a QuickTime movie extension")
@MainActor
func mobileRecordingOutputExtension() throws {
    var settings = RecordingSettings.default
    settings.saveDirectory = FileManager.default.temporaryDirectory.path
    settings.fileNameTemplate = "Meow Mobile \(UUID().uuidString)"
    settings.videoFormat = .mp4
    let url = try RecordingStore.outputURL(settings: settings, source: .mobileDevice)
    #expect(url.pathExtension == "mov")
}

@Test("Combined system and microphone recording uses a QuickTime movie container")
func combinedAudioVideoContainerNormalization() {
    var settings = RecordingSettings.default
    settings.videoFormat = .mp4
    settings.audioMode = .systemAndMicrophone

    let normalized = settings.normalized()
    #expect(normalized.videoFormat == .mov)
}

@Test("HDR and transparent recordings force compatible codecs and containers")
func advancedRecordingContainerNormalization() {
    var hdr = RecordingSettings.default
    hdr.videoFormat = .mp4
    hdr.videoCodec = .h264
    hdr.recordHDR = true
    hdr.backgroundStyle = .desktop

    let normalizedHDR = hdr.normalized()
    #expect(normalizedHDR.videoFormat == .mov)
    #expect(normalizedHDR.videoCodec == .hevc)
    #expect(normalizedHDR.recordHDR)

    var transparent = RecordingSettings.default
    transparent.videoFormat = .mp4
    transparent.videoCodec = .h264
    transparent.recordHDR = true
    transparent.backgroundStyle = .transparent

    let normalizedTransparent = transparent.normalized()
    #expect(normalizedTransparent.videoFormat == .mov)
    #expect(normalizedTransparent.videoCodec == .hevcWithAlpha)
    #expect(!normalizedTransparent.recordHDR)
}

@Test("System audio recordings use the selected audio-only extension")
@MainActor
func systemAudioRecordingOutputExtension() throws {
    var settings = RecordingSettings.default
    settings.saveDirectory = FileManager.default.temporaryDirectory.path
    settings.fileNameTemplate = "Meow Audio \(UUID().uuidString)"
    settings.videoFormat = .mov
    settings.audioFormat = .flac

    let url = try RecordingStore.outputURL(settings: settings, source: .systemAudio)
    #expect(url.pathExtension == "caf")
}

@Test("Recording file name expands tokens and removes path separators")
@MainActor
func recordingFileNameExpansion() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(
        year: 2026,
        month: 6,
        day: 14,
        hour: 9,
        minute: 8,
        second: 7
    ))!
    #expect(
        RecordingStore.expandedFileName(
            template: "Meow/Recording yyyy-MM-dd HH:mm:ss",
            date: date
        ) == "Meow-Recording 2026-06-14 09-08-07"
    )
}

@Test("Recording retention applies count, age, and storage limits")
@MainActor
func recordingRetentionPolicies() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let artifacts = (0..<8).map { index in
        RecordingArtifact(
            id: UUID(),
            source: .display,
            createdAt: now.addingTimeInterval(TimeInterval(-index * 86_400)),
            duration: 10,
            fileURL: URL(fileURLWithPath: "/tmp/\(index).mp4"),
            thumbnailURL: nil,
            width: 1920,
            height: 1080,
            fileSize: 100,
            videoCodec: .h264,
            hasSystemAudio: true,
            hasMicrophoneAudio: false
        )
    }
    let count = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 3,
        retentionDays: 0,
        maxStorageBytes: nil,
        now: now
    )
    #expect(count == Set(artifacts.prefix(3).map(\.id)))

    let age = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 2,
        maxStorageBytes: nil,
        now: now
    )
    #expect(age == Set(artifacts.prefix(3).map(\.id)))

    let storage = RecordingStore.retainedArtifactIDs(
        artifacts,
        historyLimit: 100,
        retentionDays: 0,
        maxStorageBytes: 250,
        now: now
    )
    #expect(storage == Set(artifacts.prefix(2).map(\.id)))
}
