# Third-Party Notices

Meow's voice edition uses the extracted `MeowSpeech` package instead of a
third-party speech runtime. The package uses Apple's CoreML and AVFoundation
frameworks for inference and system-voice synthesis.

## FluidAudio-derived SenseVoice implementation

- Upstream project: https://github.com/FluidInference/FluidAudio
- License: Apache License 2.0
- Included license: `THIRD_PARTY_LICENSES/FluidAudio-LICENSE.txt`
- Exact source commit and extracted files: `Packages/MeowSpeech/UPSTREAM.md`

## SenseVoice Small CoreML model

- Model repository: https://huggingface.co/FluidInference/sensevoice-small-coreml
- Exact revision and artifact checksums: `Sources/Models/SpeechModels.swift`
- Model license: `sensevoice-upstream`, linking to the upstream SenseVoice
  repository's MIT license
- Included license: `THIRD_PARTY_LICENSES/SenseVoice-LICENSE.txt`

The model is downloaded separately after the user confirms the download.
