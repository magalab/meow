import Foundation
import MeowSpeechCore

public struct MossTTSNanoSamplingDefaults: Codable, Sendable, Equatable {
    public let textTemperature: Float
    public let audioTemperature: Float
    public let audioTopP: Float
    public let audioRepetitionPenalty: Float

    public init(
        textTemperature: Float = 1.5,
        audioTemperature: Float = 1.7,
        audioTopP: Float = 0.8,
        audioRepetitionPenalty: Float = 1.2
    ) {
        self.textTemperature = textTemperature
        self.audioTemperature = audioTemperature
        self.audioTopP = audioTopP
        self.audioRepetitionPenalty = audioRepetitionPenalty
    }
}

/// Model-side token IDs and prompt template data.
///
/// The CoreML graph keeps prompt construction outside the model, so these
/// values must come from the same model revision as the downloaded graphs.
public struct MossTTSNanoConfig: Decodable, Sendable, Equatable {
    public let nVQ: Int
    public let audioCodebookSizes: [Int]
    public let audioPadTokenID: Int32
    public let audioStartTokenID: Int32
    public let audioEndTokenID: Int32
    public let audioUserSlotTokenID: Int32
    public let audioAssistantSlotTokenID: Int32
    public let sampleRate: Int
    public let maxPrefillRows: Int
    public let userPromptPrefixTokenIDs: [Int32]
    public let userPromptAfterReferenceTokenIDs: [Int32]
    public let assistantPromptPrefixTokenIDs: [Int32]
    public let sampling: MossTTSNanoSamplingDefaults

    public init(
        nVQ: Int = 16,
        audioCodebookSizes: [Int]? = nil,
        audioPadTokenID: Int32 = 1024,
        audioStartTokenID: Int32 = 6,
        audioEndTokenID: Int32 = 7,
        audioUserSlotTokenID: Int32 = 8,
        audioAssistantSlotTokenID: Int32 = 9,
        sampleRate: Int = 48_000,
        maxPrefillRows: Int = 512,
        userPromptPrefixTokenIDs: [Int32] = [],
        userPromptAfterReferenceTokenIDs: [Int32] = [],
        assistantPromptPrefixTokenIDs: [Int32] = [],
        sampling: MossTTSNanoSamplingDefaults = .init()
    ) {
        self.nVQ = nVQ
        self.audioCodebookSizes = audioCodebookSizes ?? Array(repeating: 1024, count: nVQ)
        self.audioPadTokenID = audioPadTokenID
        self.audioStartTokenID = audioStartTokenID
        self.audioEndTokenID = audioEndTokenID
        self.audioUserSlotTokenID = audioUserSlotTokenID
        self.audioAssistantSlotTokenID = audioAssistantSlotTokenID
        self.sampleRate = sampleRate
        self.maxPrefillRows = maxPrefillRows
        self.userPromptPrefixTokenIDs = userPromptPrefixTokenIDs
        self.userPromptAfterReferenceTokenIDs = userPromptAfterReferenceTokenIDs
        self.assistantPromptPrefixTokenIDs = assistantPromptPrefixTokenIDs
        self.sampling = sampling
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    private enum RootKeys: String, CodingKey {
        case model
        case coreml
        case tokens
        case prompt
        case samplingDefaults = "sampling_defaults"
        case nVQ = "n_vq"
        case audioCodebookSizes = "audio_codebook_sizes"
        case audioVocabSize = "audio_vocab_size"
        case audioPadTokenID = "audio_pad_token_id"
        case audioStartTokenID = "audio_start_token_id"
        case audioEndTokenID = "audio_end_token_id"
        case audioUserSlotTokenID = "audio_user_slot_token_id"
        case audioAssistantSlotTokenID = "audio_assistant_slot_token_id"
        case sampleRate = "sampling_rate"
        case maxPrefillRows = "max_prefill_rows"
        case promptTemplates = "prompt_templates"
        case userPromptPrefixTokenIDs = "user_prompt_prefix_token_ids"
        case userPromptAfterReferenceTokenIDs = "user_prompt_after_reference_token_ids"
        case assistantPromptPrefixTokenIDs = "assistant_prompt_prefix_token_ids"
        case generationDefaults = "generation_defaults"
        case textTemperature = "text_temperature"
        case audioTemperature = "audio_temperature"
        case audioTopP = "audio_top_p"
        case audioRepetitionPenalty = "audio_repetition_penalty"
    }

    private enum ModelKeys: String, CodingKey {
        case nVQ = "n_vq"
        case audioCodebookSize = "audio_codebook_size"
        case sampleRate = "sample_rate"
    }

    private enum CoreMLKeys: String, CodingKey {
        case prefillRows = "prefill_rows"
    }

    private enum TokenKeys: String, CodingKey {
        case audioPad = "audio_pad"
        case audioStart = "audio_start"
        case audioEnd = "audio_end"
        case audioUserSlot = "audio_user_slot"
        case audioAssistantSlot = "audio_assistant_slot"
    }

    private enum PromptKeys: String, CodingKey {
        case voiceClonePrefix = "voice_clone_prefix"
        case voiceCloneAfterReference = "voice_clone_after_reference"
        case assistantSuffix = "assistant_suffix"
    }

    private enum SamplingKeys: String, CodingKey {
        case textTemperature = "text_temperature"
        case audioTemperature = "audio_temperature"
        case audioTopP = "audio_top_p"
        case audioRepetitionPenalty = "audio_repetition_penalty"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)
        let model = try? container.nestedContainer(keyedBy: ModelKeys.self, forKey: .model)
        let coreml = try? container.nestedContainer(keyedBy: CoreMLKeys.self, forKey: .coreml)
        let tokens = try? container.nestedContainer(keyedBy: TokenKeys.self, forKey: .tokens)
        let prompt = try? container.nestedContainer(keyedBy: PromptKeys.self, forKey: .prompt)
        let samplingDefaults = try? container.nestedContainer(
            keyedBy: SamplingKeys.self,
            forKey: .samplingDefaults
        )
        let generationDefaults = try? container.nestedContainer(
            keyedBy: SamplingKeys.self,
            forKey: .generationDefaults
        )
        let codebookSizes = try container.decodeIfPresent([Int].self, forKey: .audioCodebookSizes)
        let nestedCodebookSize = try model?.decodeIfPresent(Int.self, forKey: .audioCodebookSize)
        let resolvedNVQ = try model?.decodeIfPresent(Int.self, forKey: .nVQ)
            ?? container.decodeIfPresent(Int.self, forKey: .nVQ)
            ?? codebookSizes?.count
            ?? 16
        let audioVocabSize = try container.decodeIfPresent(Int32.self, forKey: .audioVocabSize)
            ?? Int32(nestedCodebookSize ?? 1024)

        nVQ = resolvedNVQ
        audioCodebookSizes = codebookSizes ?? Array(
            repeating: Int(nestedCodebookSize ?? Int(audioVocabSize)),
            count: resolvedNVQ
        )
        audioPadTokenID = try tokens?.decodeIfPresent(Int32.self, forKey: .audioPad)
            ?? container.decodeIfPresent(Int32.self, forKey: .audioPadTokenID)
            ?? audioVocabSize
        audioStartTokenID = try tokens?.decodeIfPresent(Int32.self, forKey: .audioStart)
            ?? container.decodeIfPresent(Int32.self, forKey: .audioStartTokenID)
            ?? 6
        audioEndTokenID = try tokens?.decodeIfPresent(Int32.self, forKey: .audioEnd)
            ?? container.decodeIfPresent(Int32.self, forKey: .audioEndTokenID)
            ?? 7
        audioUserSlotTokenID = try tokens?.decodeIfPresent(Int32.self, forKey: .audioUserSlot)
            ?? container.decodeIfPresent(Int32.self, forKey: .audioUserSlotTokenID)
            ?? 8
        audioAssistantSlotTokenID = try tokens?.decodeIfPresent(
            Int32.self,
            forKey: .audioAssistantSlot
        ) ?? container.decodeIfPresent(
            Int32.self,
            forKey: .audioAssistantSlotTokenID
        ) ?? 9
        sampleRate = try model?.decodeIfPresent(Int.self, forKey: .sampleRate)
            ?? container.decodeIfPresent(Int.self, forKey: .sampleRate)
            ?? 48_000
        maxPrefillRows = try coreml?.decodeIfPresent(Int.self, forKey: .prefillRows)
            ?? container.decodeIfPresent(Int.self, forKey: .maxPrefillRows)
            ?? 512

        let legacyTemplates = try? container.nestedContainer(
            keyedBy: RootKeys.self,
            forKey: .promptTemplates
        )
        let nestedPrefix = try prompt?.decodeIfPresent([Int32].self, forKey: .voiceClonePrefix)
        let nestedAfterReference = try prompt?.decodeIfPresent(
            [Int32].self,
            forKey: .voiceCloneAfterReference
        )
        let nestedAssistantSuffix = try prompt?.decodeIfPresent(
            [Int32].self,
            forKey: .assistantSuffix
        )
        let legacyPrefix: [Int32]? = try container.decodeIfPresent(
            [Int32].self,
            forKey: .userPromptPrefixTokenIDs
        ) ?? (try legacyTemplates?.decodeIfPresent(
            [Int32].self,
            forKey: .userPromptPrefixTokenIDs
        ))
        let legacyAfterReference: [Int32]? = try container.decodeIfPresent(
            [Int32].self,
            forKey: .userPromptAfterReferenceTokenIDs
        ) ?? (try legacyTemplates?.decodeIfPresent(
            [Int32].self,
            forKey: .userPromptAfterReferenceTokenIDs
        ))
        let legacyAssistantPrefix: [Int32]? = try container.decodeIfPresent(
            [Int32].self,
            forKey: .assistantPromptPrefixTokenIDs
        ) ?? (try legacyTemplates?.decodeIfPresent(
            [Int32].self,
            forKey: .assistantPromptPrefixTokenIDs
        ))
        userPromptPrefixTokenIDs = Self.removeTrailing(
            nestedPrefix ?? legacyPrefix ?? [],
            token: audioStartTokenID
        )
        userPromptAfterReferenceTokenIDs = Self.removeLeading(
            nestedAfterReference ?? legacyAfterReference ?? [],
            token: audioEndTokenID
        )
        assistantPromptPrefixTokenIDs = Self.removeTrailing(
            nestedAssistantSuffix ?? legacyAssistantPrefix ?? [],
            token: audioStartTokenID
        )

        let resolvedSampling = samplingDefaults ?? generationDefaults
        let textTemperature = try resolvedSampling?.decodeIfPresent(
            Float.self,
            forKey: .textTemperature
        ) ?? container.decodeIfPresent(Float.self, forKey: .textTemperature) ?? 1.5
        let audioTemperature = try resolvedSampling?.decodeIfPresent(
            Float.self,
            forKey: .audioTemperature
        ) ?? container.decodeIfPresent(Float.self, forKey: .audioTemperature) ?? 1.7
        let audioTopP = try resolvedSampling?.decodeIfPresent(
            Float.self,
            forKey: .audioTopP
        ) ?? container.decodeIfPresent(Float.self, forKey: .audioTopP) ?? 0.8
        let audioRepetitionPenalty = try resolvedSampling?.decodeIfPresent(
            Float.self,
            forKey: .audioRepetitionPenalty
        ) ?? container.decodeIfPresent(Float.self, forKey: .audioRepetitionPenalty) ?? 1.2
        sampling = MossTTSNanoSamplingDefaults(
            textTemperature: textTemperature,
            audioTemperature: audioTemperature,
            audioTopP: audioTopP,
            audioRepetitionPenalty: audioRepetitionPenalty
        )
    }

    private static func removeTrailing(_ values: [Int32], token: Int32) -> [Int32] {
        values.last == token ? Array(values.dropLast()) : values
    }

    private static func removeLeading(_ values: [Int32], token: Int32) -> [Int32] {
        values.first == token ? Array(values.dropFirst()) : values
    }
}

public struct MossTTSNanoPrompt: Sendable, Equatable {
    public let rows: [[Int32]]
    public let inputLength: Int

    public init(rows: [[Int32]], inputLength: Int) {
        self.rows = rows
        self.inputLength = inputLength
    }
}

public struct MossTTSNanoPromptBuilder: Sendable {
    public let configuration: MossTTSNanoConfig

    public init(configuration: MossTTSNanoConfig) {
        self.configuration = configuration
    }

    public func buildVoiceClonePrompt(
        promptAudioCodes: [[Int32]],
        textTokenIDs: [Int32]
    ) throws -> MossTTSNanoPrompt {
        let prefix = configuration.userPromptPrefixTokenIDs
            + [configuration.audioStartTokenID]
        let suffix = [configuration.audioEndTokenID]
            + configuration.userPromptAfterReferenceTokenIDs
            + textTokenIDs
            + configuration.assistantPromptPrefixTokenIDs
            + [configuration.audioStartTokenID]

        var rows = textRows(prefix)
        rows.append(contentsOf: audioRows(promptAudioCodes))
        rows.append(contentsOf: textRows(suffix))
        guard rows.count <= configuration.maxPrefillRows else {
            throw SpeechError.invalidAudio(
                "MOSS-TTS-Nano prompt exceeds the CoreML prefill limit."
            )
        }

        let inputLength = rows.count
        let padding = configuration.maxPrefillRows - inputLength
        if padding > 0 {
            rows.append(contentsOf: textRows(
                Array(repeating: configuration.audioPadTokenID, count: padding)
            ))
        }
        return MossTTSNanoPrompt(rows: rows, inputLength: inputLength)
    }

    private func textRows(_ tokenIDs: [Int32]) -> [[Int32]] {
        tokenIDs.map { tokenID in
            [tokenID] + Array(repeating: configuration.audioPadTokenID, count: configuration.nVQ)
        }
    }

    private func audioRows(_ codes: [[Int32]]) -> [[Int32]] {
        codes.map { codeRow in
            [configuration.audioUserSlotTokenID]
                + Array(codeRow.prefix(configuration.nVQ))
                + Array(
                    repeating: configuration.audioPadTokenID,
                    count: max(0, configuration.nVQ - codeRow.count)
                )
        }
    }
}
