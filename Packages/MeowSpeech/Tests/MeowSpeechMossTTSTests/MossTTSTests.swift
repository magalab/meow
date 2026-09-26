import MeowSpeechCore
import MeowSpeechMossTTS
import Testing
import Foundation

private func protobufVarint(_ input: UInt64) -> [UInt8] {
    var value = input
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        if value != 0 { byte |= 0x80 }
        bytes.append(byte)
    } while value != 0
    return bytes
}

private func protobufPiece(_ text: String, score: Float) -> [UInt8] {
    let textBytes = Array(text.utf8)
    var piece: [UInt8] = [0x0A]
    piece += protobufVarint(UInt64(textBytes.count))
    piece += textBytes
    piece += [0x15]
    piece += withUnsafeBytes(of: score) { Array($0) }
    return [0x0A] + protobufVarint(UInt64(piece.count)) + piece
}

@Test("MOSS TTS CoreML layout matches the published graph set")
func mossTTSModelLayout() {
    let layout = MossTTSNanoModelLayout.current

    #expect(layout.modelNames == [
        "MossNano-Prefill-T512-M1024-fp16.mlmodelc",
        "MossNano-Step-M1024-fp16.mlmodelc",
        "MossNano-Frame-fp16.mlmodelc",
        "MossNano-CodecStep-fp16.mlmodelc",
        "MossNano-CodecDecoder-fp16.mlmodelc",
        "MossNano-CodecEncoder-fp32.mlmodelc",
    ])
    #expect(layout.requiredRelativePaths == layout.modelNames + ["config.json", "tokenizer.model"])
    #expect(layout.optionalRelativePaths == ["voices/en_2.json", "voices/zh_1.json"])
}

@Test("MOSS TTS config decodes prompt templates and model defaults")
func mossTTSConfigDecoding() throws {
    let data = Data(#"""
    {
      "n_vq": 16,
      "audio_pad_token_id": 1024,
      "audio_start_token_id": 6,
      "audio_end_token_id": 7,
      "audio_user_slot_token_id": 8,
      "audio_assistant_slot_token_id": 9,
      "sampling_rate": 48000,
      "prompt_templates": {
        "user_prompt_prefix_token_ids": [1, 2],
        "user_prompt_after_reference_token_ids": [3],
        "assistant_prompt_prefix_token_ids": [4, 5]
      },
      "generation_defaults": {
        "text_temperature": 1.0,
        "audio_temperature": 0.8,
        "audio_top_p": 0.95,
        "audio_repetition_penalty": 1.2
      }
    }
    """#.utf8)

    let configuration = try MossTTSNanoConfig(data: data)
    #expect(configuration.nVQ == 16)
    #expect(configuration.sampleRate == 48_000)
    #expect(configuration.userPromptPrefixTokenIDs == [1, 2])
    #expect(configuration.assistantPromptPrefixTokenIDs == [4, 5])
    #expect(configuration.sampling.audioTopP == 0.95)
}

@Test("MOSS TTS config decodes the published nested model schema")
func mossTTSPublishedConfigDecoding() throws {
    let data = Data(#"""
    {
      "model": {
        "n_vq": 16,
        "audio_codebook_size": 1024,
        "sample_rate": 48000
      },
      "coreml": { "prefill_rows": 512 },
      "tokens": {
        "audio_start": 6,
        "audio_end": 7,
        "audio_user_slot": 8,
        "audio_assistant_slot": 9,
        "audio_pad": 1024
      },
      "prompt": {
        "voice_clone_prefix": [1, 2, 6],
        "voice_clone_after_reference": [7, 3],
        "assistant_suffix": [4, 6]
      },
      "sampling_defaults": {
        "text_temperature": 1.5,
        "audio_temperature": 1.7,
        "audio_top_p": 0.8,
        "audio_repetition_penalty": 1.0
      }
    }
    """#.utf8)

    let configuration = try MossTTSNanoConfig(data: data)
    #expect(configuration.nVQ == 16)
    #expect(configuration.audioCodebookSizes == Array(repeating: 1024, count: 16))
    #expect(configuration.maxPrefillRows == 512)
    #expect(configuration.userPromptPrefixTokenIDs == [1, 2])
    #expect(configuration.userPromptAfterReferenceTokenIDs == [3])
    #expect(configuration.assistantPromptPrefixTokenIDs == [4])
    #expect(configuration.sampling.audioRepetitionPenalty == 1.0)
}

@Test("MOSS TTS prompt builder pads the fixed CoreML prefill shape")
func mossTTSPromptBuilder() throws {
    let configuration = MossTTSNanoConfig(
        nVQ: 2,
        maxPrefillRows: 10,
        userPromptPrefixTokenIDs: [1],
        userPromptAfterReferenceTokenIDs: [2],
        assistantPromptPrefixTokenIDs: [3]
    )
    let prompt = try MossTTSNanoPromptBuilder(configuration: configuration)
        .buildVoiceClonePrompt(
            promptAudioCodes: [[10, 11]],
            textTokenIDs: [20]
        )

    #expect(prompt.inputLength == 8)
    #expect(prompt.rows.count == 10)
    #expect(prompt.rows[0] == [1, 1024, 1024])
    #expect(prompt.rows[1] == [6, 1024, 1024])
    #expect(prompt.rows[2] == [8, 10, 11])
    #expect(prompt.rows[3] == [7, 1024, 1024])
    #expect(prompt.rows[4] == [2, 1024, 1024])
    #expect(prompt.rows[5] == [20, 1024, 1024])
    #expect(prompt.rows[6] == [3, 1024, 1024])
    #expect(prompt.rows[7] == [6, 1024, 1024])
    #expect(prompt.rows[8] == [1024, 1024, 1024])
    #expect(prompt.rows[9] == [1024, 1024, 1024])
}

@Test("MOSS TTS tokenizer handles SentencePiece vocabulary and spaces")
func mossTTSTokenizer() throws {
    var modelData: [UInt8] = []
    modelData += protobufPiece("<unk>", score: -10)
    modelData += protobufPiece("▁hello", score: 0)
    modelData += protobufPiece("▁world", score: 0)
    modelData += protobufPiece("▁", score: -1)
    let tokenizer = try MossTTSNanoTokenizer(modelData: Data(modelData))

    #expect(tokenizer.encode("hello world") == [1, 2])
}

@Test("MOSS TTS model loader reports an incomplete model directory")
func mossTTSModelLoaderRequiresAllArtifacts() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-MOSS-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let loader = MossTTSNanoModelLoader(modelDirectory: directory)
    do {
        try await loader.prepare()
        #expect(Bool(false), "An empty model directory must not be loadable")
    } catch let error as SpeechError {
        #expect(error == .modelUnavailable)
    } catch {
        #expect(Bool(false), "Unexpected model loader error")
    }
}

@Test("MOSS TTS loader reads preset voice code rows")
func mossTTSPresetVoiceCodes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-MOSS-Voice-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("voices", isDirectory: true),
        withIntermediateDirectories: true
    )
    let voiceURL = directory.appendingPathComponent("voices/test.json")
    try Data(#"[[1, 2], [3, 4]]"#.utf8).write(to: voiceURL)

    let loader = MossTTSNanoModelLoader(
        modelDirectory: directory,
        layout: MossTTSNanoModelLayout(presetVoicePaths: ["voices/test.json"])
    )
    #expect(await loader.presetVoiceIDs() == ["test"])
    #expect(try await loader.presetVoiceCodes(for: "test") == [[1, 2], [3, 4]])
}

@Test("MOSS TTS preset voice IDs reject path traversal")
func mossTTSPresetVoiceIDValidation() async {
    let loader = MossTTSNanoModelLoader(
        modelDirectory: FileManager.default.temporaryDirectory,
        layout: MossTTSNanoModelLayout(presetVoicePaths: ["voices/test.json"])
    )
    do {
        _ = try await loader.presetVoiceCodes(for: "../test")
        #expect(Bool(false), "A preset voice ID must not escape the model directory")
    } catch let error as SpeechError {
        #expect(error == .invalidAudio("MOSS-TTS-Nano voice ID is invalid."))
    } catch {
        #expect(Bool(false), "Unexpected preset voice validation error")
    }
}

@Test("Installed MOSS TTS CoreML graphs can be loaded")
func mossTTSModelSmokeTest() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["MEOW_MOSS_TTS_MODEL_DIR"] else {
        return
    }

    let loader = MossTTSNanoModelLoader(
        modelDirectory: URL(fileURLWithPath: modelPath),
        computePolicy: .cpuAndGPU
    )
    try await loader.prepare()
    #expect(await loader.isReady)
}

@Test("Installed MOSS TTS emits the first audio chunk incrementally")
func mossTTSSynthesisSmokeTest() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["MEOW_MOSS_TTS_MODEL_DIR"] else {
        return
    }

    let synthesizer = MossTTSNanoSynthesizer(
        modelDirectory: URL(fileURLWithPath: modelPath),
        maxFrames: 8,
        computePolicy: .cpuAndGPU
    )
    try await synthesizer.prepare()
    var stream = synthesizer.synthesize(
        text: "你好，Meow。",
        voice: VoiceProfile(id: "zh_1", name: "Chinese")
    ).makeAsyncIterator()
    let start = Date()
    var firstChunkDelay: TimeInterval?
    var chunkCount = 0
    var sampleCount = 0

    while let chunk = try await stream.next() {
        if firstChunkDelay == nil {
            firstChunkDelay = Date().timeIntervalSince(start)
        }
        chunkCount += 1
        sampleCount += chunk.samples.count
    }

    #expect(chunkCount > 0)
    #expect(sampleCount > 0)
    if let firstChunkDelay {
        print("[MOSS TTS smoke] first audio chunk: \(firstChunkDelay)s, chunks: \(chunkCount)")
    }
}

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
