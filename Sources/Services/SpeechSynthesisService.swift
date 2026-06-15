@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechSynthesisService: ObservableObject {
    @Published private(set) var state: TtsSynthesisState = .idle
    @Published private(set) var result: TtsAudioResult?

    var onNeedsModel: (() -> Void)?

    private let modelStore: TtsModelStore
    private let engine = TtsSynthesisEngine()
    private let audioPlayer = TtsAudioPlayer()
    private var synthesisTask: Task<Void, Never>?
    private var synthesisID: UUID?
    private var currentSettings = TtsSettings.default

    init(modelStore: TtsModelStore) {
        self.modelStore = modelStore
    }

    func apply(settings: TtsSettings) {
        let normalized = settings.normalized()
        let shouldUnload = currentSettings.model != normalized.model
        currentSettings = normalized
        if !normalized.enabled {
            clearResult()
        } else if shouldUnload {
            clearResult()
            Task { await engine.unload() }
        }
    }

    func synthesize(text: String, settings: TtsSettings) {
        let normalizedSettings = settings.normalized()
        let normalizedText = Self.normalizedText(text)
        guard normalizedSettings.enabled else { return }
        guard !normalizedText.isEmpty else {
            state = .failed(L10n.ttsErrorEmptyText)
            return
        }
        guard !state.isGenerating else { return }
        guard let modelDirectory = modelStore.configurationDirectory(for: normalizedSettings.model) else {
            state = .needsModel
            onNeedsModel?()
            return
        }

        audioPlayer.stop()
        synthesisTask?.cancel()
        let synthesisID = UUID()
        self.synthesisID = synthesisID
        result = nil
        state = .loadingModel
        let chunks = Self.chunks(from: normalizedText)

        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await engine.synthesize(
                    chunks: chunks,
                    fullText: normalizedText,
                    model: normalizedSettings.model,
                    modelDirectory: modelDirectory,
                    voiceID: normalizedSettings.voiceID,
                    speed: 1
                ) { [weak self] progress in
                    DispatchQueue.main.async {
                        guard let self, self.synthesisID == synthesisID else { return }
                        self.state = .synthesizing(progress)
                    }
                }
                try Task.checkCancellation()
                guard self.synthesisID == synthesisID else { return }
                self.result = result
                self.state = .ready
                self.play()
            } catch is CancellationError {
                if self.synthesisID == synthesisID {
                    self.state = .idle
                }
            } catch {
                if self.synthesisID == synthesisID {
                    self.state = .failed(error.localizedDescription)
                }
            }
            if self.synthesisID == synthesisID {
                self.synthesisTask = nil
                self.synthesisID = nil
            }
        }
    }

    func cancel() {
        synthesisID = nil
        synthesisTask?.cancel()
        synthesisTask = nil
        audioPlayer.stop()
        if state != .idle {
            state = result == nil ? .idle : .ready
        }
    }

    func play() {
        guard let result else { return }
        do {
            try audioPlayer.play(result) { [weak self] in
                guard let self else { return }
                self.state = self.result == nil ? .idle : .ready
            }
            state = .playing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func pauseOrResume() {
        switch state {
        case .playing:
            audioPlayer.pause()
            state = .paused
        case .paused:
            audioPlayer.resume()
            state = .playing
        default:
            break
        }
    }

    func stopPlayback() {
        audioPlayer.stop()
        state = result == nil ? .idle : .ready
    }

    func clearResult() {
        cancel()
        result = nil
        state = .idle
    }

    func unloadModel() {
        clearResult()
        Task { await engine.unload() }
    }

    func exportResult(to url: URL) throws {
        guard let result else { throw TtsExportError.noAudio }
        try Self.writeWAV(result, to: url)
    }

    nonisolated static func normalizedText(_ text: String) -> String {
        let collapsed = normalizedKeyboardSymbols(in: text)
            .replacingOccurrences(of: "❓", with: "?")
            .replacingOccurrences(of: "❔", with: "?")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = containsHan(collapsed) ? normalizedChineseText(collapsed) : collapsed
        return trimBoundaryPunctuation(in: normalized)
    }

    private nonisolated static func normalizedKeyboardSymbols(in text: String) -> String {
        let replacements: [(String, String)] = [
            ("⌘", " Command "),
            ("⌥", " Option "),
            ("⌃", " Control "),
            ("⇧", " Shift "),
            ("⇪", " Caps Lock "),
            ("⎋", " Escape "),
            ("⏎", " Return "),
            ("⌤", " Enter "),
            ("⌫", " Delete "),
            ("⌦", " Forward Delete "),
            ("⇥", " Tab "),
            ("⇤", " Shift Tab "),
            ("␣", " Space "),
            ("↑", " Up Arrow "),
            ("↓", " Down Arrow "),
            ("←", " Left Arrow "),
            ("→", " Right Arrow "),
            ("", " Apple "),
        ]
        let symbolExpanded = replacements.reduce(text) { result, replacement in
            result.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
        return normalizedShortcutLetters(in: symbolExpanded)
    }

    private nonisolated static func normalizedShortcutLetters(in text: String) -> String {
        let pattern = #"\b(Command|Option|Control|Shift)\s+([A-Z])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        var result = ""
        var lastLocation = 0
        let fullRange = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: text, range: fullRange) {
            guard match.numberOfRanges == 3 else { continue }
            let matchRange = match.range(at: 0)
            let modifier = nsText.substring(with: match.range(at: 1))
            let letter = nsText.substring(with: match.range(at: 2))
            result += nsText.substring(with: NSRange(location: lastLocation, length: matchRange.location - lastLocation))
            result += "\(modifier) plus \(spokenLetterName(letter))"
            lastLocation = matchRange.location + matchRange.length
        }
        result += nsText.substring(from: lastLocation)
        return result
    }

    private nonisolated static func spokenLetterName(_ letter: String) -> String {
        switch letter.uppercased() {
        case "A": return "able"
        case "B": return "bee"
        case "C": return "sea"
        case "D": return "deep"
        case "E": return "easy"
        case "F": return "effort"
        case "G": return "gee"
        case "H": return "hotel"
        case "I": return "eye"
        case "J": return "jay"
        case "K": return "cake"
        case "L": return "else"
        case "M": return "empty"
        case "N": return "entry"
        case "O": return "open"
        case "P": return "pea"
        case "Q": return "queue"
        case "R": return "are"
        case "S": return "essay"
        case "T": return "tea"
        case "U": return "you"
        case "V": return "vee"
        case "W": return "double you"
        case "X": return "x ray"
        case "Y": return "why"
        case "Z": return "zebra"
        default: return letter
        }
    }

    private nonisolated static func trimBoundaryPunctuation(in text: String) -> String {
        let leadingPunctuation = CharacterSet(charactersIn: "，。！？!?；;,:：、")
        let trailingSoftPunctuation = CharacterSet(charactersIn: "，,；;:：、")
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = trimmed.unicodeScalars.first, leadingPunctuation.contains(first) {
            trimmed.removeFirst()
        }
        while let last = trimmed.unicodeScalars.last, trailingSoftPunctuation.contains(last) {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private nonisolated static func normalizedChineseText(_ text: String) -> String {
        text
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: ".", with: "。")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "!", with: "！")
            .replacingOccurrences(of: ";", with: "；")
            .replacingOccurrences(of: ":", with: "：")
            .replacingOccurrences(of: " ，", with: "，")
            .replacingOccurrences(of: "， ", with: "，")
            .replacingOccurrences(of: " 。", with: "。")
            .replacingOccurrences(of: "。 ", with: "。")
            .replacingOccurrences(of: " ？", with: "？")
            .replacingOccurrences(of: "？ ", with: "？")
            .replacingOccurrences(of: " ！", with: "！")
            .replacingOccurrences(of: "！ ", with: "！")
            .replacingOccurrences(of: " ；", with: "；")
            .replacingOccurrences(of: "； ", with: "；")
            .replacingOccurrences(of: " ：", with: "：")
            .replacingOccurrences(of: "： ", with: "：")
    }

    nonisolated static func chunks(from text: String, maximumLength: Int = 400) -> [String] {
        let sentenceEndings = CharacterSet(charactersIn: "。！？!?；;\n")
        guard text.count > maximumLength else {
            return text.isEmpty ? [] : [text]
        }
        var chunks: [String] = []
        var current = ""

        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            let reachedBoundary = sentenceEndings.contains(scalar)
            let minimumChunkLength = max(1, maximumLength / 3)
            if current.count >= maximumLength || (reachedBoundary && current.count >= minimumChunkLength) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chunks.append(trimmed)
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            chunks.append(remainder)
        }
        return chunks
    }

    nonisolated static func writeWAV(_ result: TtsAudioResult, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(result.sampleRate),
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(result.samples.count)
        ), let channel = buffer.floatChannelData?[0]
        else {
            throw TtsExportError.invalidAudio
        }

        buffer.frameLength = AVAudioFrameCount(result.samples.count)
        result.samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: source.count)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}

private actor TtsSynthesisEngine {
    private static let leadingSilenceSeconds: Double = 0.08
    private static let interChunkSilenceSeconds: Double = 0.12

    private var synthesizer: SherpaOnnxSynthesizer?
    private var loadedModel: TtsModelKind?
    private var loadedDirectory: URL?

    func synthesize(
        chunks: [String],
        fullText: String,
        model: TtsModelKind,
        modelDirectory: URL,
        voiceID: Int32,
        speed: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TtsAudioResult {
        try Task.checkCancellation()
        let activeSynthesizer: SherpaOnnxSynthesizer
        if let synthesizer, loadedModel == model, loadedDirectory == modelDirectory {
            activeSynthesizer = synthesizer
        } else {
            let synthesizer = try SherpaOnnxSynthesizer(model: model, modelDirectory: modelDirectory)
            self.synthesizer = synthesizer
            loadedModel = model
            loadedDirectory = modelDirectory
            activeSynthesizer = synthesizer
        }

        var combinedSamples: [Float] = []
        var sampleRate = 0
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunkResult = try await activeSynthesizer.synthesize(
                text: chunk,
                voiceID: voiceID,
                speed: speed
            ) { chunkProgress in
                let completed = Double(index) / Double(max(chunks.count, 1))
                let current = chunkProgress / Double(max(chunks.count, 1))
                progress(completed + current)
            }
            if sampleRate == 0 {
                sampleRate = chunkResult.sampleRate
            } else if sampleRate != chunkResult.sampleRate {
                throw TtsExportError.inconsistentSampleRate
            }
            if combinedSamples.isEmpty {
                combinedSamples.append(
                    contentsOf: repeatElement(0, count: Int(Double(sampleRate) * Self.leadingSilenceSeconds))
                )
            } else {
                combinedSamples.append(
                    contentsOf: repeatElement(0, count: Int(Double(sampleRate) * Self.interChunkSilenceSeconds))
                )
            }
            combinedSamples.append(contentsOf: chunkResult.samples)
        }
        guard !combinedSamples.isEmpty, sampleRate > 0 else {
            throw SherpaOnnxSynthesizerError.emptyAudio
        }
        progress(1)
        return TtsAudioResult(
            samples: combinedSamples,
            sampleRate: sampleRate,
            text: fullText,
            voiceID: voiceID
        )
    }

    func unload() {
        synthesizer = nil
        loadedModel = nil
        loadedDirectory = nil
    }
}

private enum TtsExportError: LocalizedError {
    case noAudio
    case invalidAudio
    case inconsistentSampleRate

    var errorDescription: String? {
        switch self {
        case .noAudio:
            return L10n.ttsErrorNoAudio
        case .invalidAudio, .inconsistentSampleRate:
            return L10n.ttsErrorExportFailed
        }
    }
}
