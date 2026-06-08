import AppKit
import AVFAudio
import Foundation

@MainActor
final class SpeechHistoryStore: ObservableObject {
    @Published private(set) var entries: [SpeechHistoryEntry] = []

    let storageDirectory: URL
    private let recordingsDirectory: URL
    private let indexURL: URL
    private var audioPlayer: AVAudioPlayer?

    init(fileManager: FileManager = .default) {
        let appSupport = Self.appSupportDirectory(fileManager: fileManager)
        storageDirectory = appSupport
            .appendingPathComponent("Meow", isDirectory: true)
            .appendingPathComponent("ASRHistory", isDirectory: true)
        recordingsDirectory = storageDirectory.appendingPathComponent("Recordings", isDirectory: true)
        indexURL = storageDirectory.appendingPathComponent("index.json")
        load()
    }

    func append(
        text: String,
        language: String?,
        duration: TimeInterval,
        samples: [Float],
        retentionDays: Int
    ) throws {
        cleanup(retentionDays: retentionDays)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        let audioURL = recordingsDirectory.appendingPathComponent(fileName)
        try Self.writeWAV(samples: samples, sampleRate: 16_000, to: audioURL)

        let entry = SpeechHistoryEntry(
            id: id,
            text: text,
            language: language,
            createdAt: Date(),
            duration: duration,
            audioFileName: fileName
        )
        entries.insert(entry, at: 0)
        do {
            try save()
        } catch {
            entries.removeAll { $0.id == entry.id }
            try? FileManager.default.removeItem(at: audioURL)
            throw error
        }
    }

    func delete(_ entry: SpeechHistoryEntry) {
        try? FileManager.default.removeItem(at: audioURL(for: entry))
        entries.removeAll { $0.id == entry.id }
        try? save()
    }

    func clear() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? FileManager.default.removeItem(at: storageDirectory)
        entries = []
    }

    func cleanup(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        let expired = entries.filter { $0.createdAt < cutoff }
        for entry in expired {
            try? FileManager.default.removeItem(at: audioURL(for: entry))
        }
        if !expired.isEmpty {
            entries.removeAll { $0.createdAt < cutoff }
            try? save()
        }
    }

    func play(_ entry: SpeechHistoryEntry) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL(for: entry))
            audioPlayer?.play()
        } catch {
            NSLog("[Meow] Failed to play speech history audio: \(error.localizedDescription)")
        }
    }

    func copyText(_ entry: SpeechHistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(storageDirectory)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SpeechHistoryEntry].self, from: data)
        else {
            entries = []
            cleanupOrphanedRecordings(keeping: [])
            return
        }
        entries = decoded
            .filter { FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
        cleanupOrphanedRecordings(keeping: Set(entries.map(\.audioFileName)))
        try? save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    private func audioURL(for entry: SpeechHistoryEntry) -> URL {
        recordingsDirectory.appendingPathComponent(entry.audioFileName)
    }

    private nonisolated static func appSupportDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    private func cleanupOrphanedRecordings(keeping audioFileNames: Set<String>) {
        guard let recordingURLs = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in recordingURLs where url.pathExtension.lowercased() == "wav" {
            if !audioFileNames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private nonisolated static func writeWAV(samples: [Float], sampleRate: UInt32, to url: URL) throws {
        var pcm = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32(UInt32(36 + pcm.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32(16)
        data.appendUInt16(1)
        data.appendUInt16(1)
        data.appendUInt32(sampleRate)
        data.appendUInt32(sampleRate * 2)
        data.appendUInt16(2)
        data.appendUInt16(16)
        data.appendASCII("data")
        data.appendUInt32(UInt32(pcm.count))
        data.append(pcm)
        try data.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
