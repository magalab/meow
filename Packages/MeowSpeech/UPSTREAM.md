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
  - Removed FluidAudio logging, registry, and unrelated ASR/TTS/VAD code.
- Source license: FluidAudio is Apache-2.0. The CoreML model repository declares
  `sensevoice-upstream`, linking to the upstream SenseVoice MIT license. The
  corresponding license text is vendored in `THIRD_PARTY_LICENSES/SenseVoice-LICENSE.txt`.
- The opt-in test fixture `Tests/MeowSpeechSenseVoiceTests/Fixtures/01-validation-request-21.4s.wav`
  is copied from the upstream FluidAudio test fixture for local parity checks;
  SHA-256: `ad9e59cad579382e742af2265280396c24c174f325e172ff5e5862a2457640d9`.

## MOSS-TTS-Nano

The CoreML model conversion is published at
`https://huggingface.co/FluidInference/moss-tts-nano-coreml` and is based on
the Apache-2.0 MOSS-TTS-Nano and MOSS-Audio-Tokenizer releases. The published
graph set is:

- `MossNano-Prefill-T512-M1024-fp16`
- `MossNano-Step-M1024-fp16`
- `MossNano-Frame-fp16`
- `MossNano-CodecStep-fp16`
- `MossNano-CodecDecoder-fp16`
- `MossNano-CodecEncoder-fp32`

`MeowSpeechMossTTS` now owns the model layout, CoreML graph loader, model-side
configuration decoding, prompt construction, SentencePiece tokenizer, the
prefill → frame → autoregressive step loop, and full-frame codec decoding.
These pieces are covered by package-level shape and contract tests, but the
real CoreML artifacts still need an opt-in device smoke test before they are
connected to a production device path.

The package now also exposes preset-voice loading, reference-audio encoding
through `MossNano-CodecEncoder`, and a model-directory synthesizer that
downmixes decoded stereo to Meow's mono `AudioChunk` contract. The voice
edition app now owns the pinned manifest, checksum-verified download, model
selection UI, and default synthesizer factory wiring. The remaining work is
optional `MossNano-CodecStep` streaming and parity testing against the real
CoreML artifacts on Apple Silicon. The no-argument public synthesizer remains
an explicit placeholder for package-only callers that have not supplied a
model directory.

The current public `FluidAudio` main branch inspected on 2026-09-25 does not
contain the `Sources/FluidAudio/TTS/MossTtsNano` path referenced by the model
card, so the implementation will be extracted from the published model I/O
contract rather than copied from an unavailable upstream source tree.
