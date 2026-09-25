import MeowSpeechCore
import MeowSpeechMossTTS
import Testing

@Test("MOSS TTS placeholder preserves the streaming failure contract")
func mossTTSPlaceholderContract() async {
    var stream = MossTTSNanoSynthesizer().synthesize(
        text: "Hello from Meow",
        voice: VoiceProfile(id: "default", name: "Default")
    ).makeAsyncIterator()

    do {
        _ = try await stream.next()
        #expect(Bool(false), "The placeholder must not emit audio before MOSS is enabled")
    } catch let error as SpeechError {
        #expect(error == .unsupported("MOSS-TTS-Nano has not been enabled in this build."))
    } catch {
        #expect(Bool(false), "Unexpected placeholder error: \(error)")
    }
}
