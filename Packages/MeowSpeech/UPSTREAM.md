# MeowSpeech upstream provenance

## SenseVoice

- Repository: https://github.com/FluidInference/FluidAudio
- Commit inspected: `3233930799e5a7ab479201b5617f618f6f43e94a`
- Model repository: https://huggingface.co/FluidInference/sensevoice-small-coreml
- Model revision: `cdea3526163035c19915d4a10268992d018ebd46`
- Imported implementation areas:
  - `Sources/FluidAudio/ASR/SenseVoice/SenseVoiceConfig.swift`
  - `Sources/FluidAudio/ASR/SenseVoice/SenseVoiceManager.swift`
  - `Sources/FluidAudio/ASR/SenseVoice/SenseVoiceModels.swift`
  - `Sources/FluidAudio/ASR/Shared/LogitsArgmax.swift`
  - `Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CTC/CtcDecoder.swift` (`decodeCtcTokenIds`)
- Local changes:
  - Replaced FluidAudio public types with `MeowSpeechCore` types.
  - Moved model downloading to Meow's existing UI-aware model store.
  - Kept only the SenseVoice CoreML inference, greedy CTC decode, and vocabulary parsing closure.
  - Removed FluidAudio logging, registry, and unrelated ASR/VAD code.
- Source license: FluidAudio is Apache-2.0. The CoreML model repository declares
  `sensevoice-upstream`, linking to the upstream SenseVoice MIT license. The
  corresponding license text is vendored in `THIRD_PARTY_LICENSES/SenseVoice-LICENSE.txt`.
- The opt-in test fixture `Tests/MeowSpeechSenseVoiceTests/Fixtures/01-validation-request-21.4s.wav`
  is copied from the upstream FluidAudio test fixture for local parity checks;
  SHA-256: `ad9e59cad579382e742af2265280396c24c174f325e172ff5e5862a2457640d9`.
