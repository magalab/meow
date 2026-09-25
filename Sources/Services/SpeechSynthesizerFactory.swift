import MeowSpeechCore

enum AppSpeechSynthesizerFactory {
    static func make() -> any SpeechSynthesizer {
        SystemSpeechSynthesizer()
    }
}
