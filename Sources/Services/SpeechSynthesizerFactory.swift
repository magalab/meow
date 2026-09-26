import Foundation
import MeowSpeechCore
import MeowSpeechMossTTS

enum AppSpeechSynthesizerFactory {
    static func make(
        model: TtsModelKind,
        modelDirectory: URL
    ) -> any SpeechSynthesizer {
        switch model {
        case .system:
            return SystemSpeechSynthesizer()
        case .mossTTSNano:
            return MossTTSNanoSynthesizer(modelDirectory: modelDirectory)
        }
    }
}
