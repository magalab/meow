import Foundation
import MeowSpeechCore
import MeowSpeechSenseVoice

/// Voice-edition composition boundary for the current ASR backend.
///
/// Application services only depend on `SpeechRecognizer`; backend construction
/// stays here so a future backend can replace SenseVoice without changing
/// recording, history, or text insertion code.
enum AppSpeechRecognizerFactory {
    static func make(modelDirectory: URL) -> any SpeechRecognizer {
        // Keep the first product path deterministic. On this host, the
        // int8 Neural Engine graph takes several minutes to specialize on its
        // first load, while the CoreML CPU path completes the same fixture in
        // under a second. Re-enable ANE after a measured device benchmark.
        SenseVoiceRecognizer(modelDirectory: modelDirectory, computePolicy: .cpuOnly)
    }
}
