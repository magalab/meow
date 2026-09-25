import Foundation

public protocol SpeechRecognizer: Sendable {
    func transcribe(
        samples: [Float],
        sampleRate: Double
    ) async throws -> TranscriptionResult
}

public protocol SpeechSynthesizer: Sendable {
    func synthesize(
        text: String,
        voice: VoiceProfile?
    ) -> AsyncThrowingStream<AudioChunk, Error>
}

public struct TranscriptionResult: Sendable, Equatable {
    public let text: String
    public let language: String?
    public let duration: TimeInterval

    public init(text: String, language: String? = nil, duration: TimeInterval = 0) {
        self.text = text
        self.language = language
        self.duration = duration
    }
}

public struct AudioChunk: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Int
    public let isFinal: Bool

    public init(samples: [Float], sampleRate: Int, isFinal: Bool = false) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.isFinal = isFinal
    }
}

public struct VoiceProfile: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let language: String?

    public init(id: String, name: String, language: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
    }
}

public enum SpeechError: Error, LocalizedError, Sendable, Equatable {
    case modelUnavailable
    case modelLoadFailed(String)
    case invalidAudio(String)
    case inferenceFailed(String)
    case cancelled
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "The speech model is not installed."
        case let .modelLoadFailed(message), let .invalidAudio(message),
             let .inferenceFailed(message), let .unsupported(message):
            return message
        case .cancelled:
            return "Speech processing was cancelled."
        }
    }
}

public struct SpeechModelArtifact: Sendable, Equatable, Identifiable {
    public let id: String
    public let relativePath: String
    public let remoteURL: URL
    public let sha256: String
    public let byteCount: Int64?

    public init(
        id: String,
        relativePath: String,
        remoteURL: URL,
        sha256: String,
        byteCount: Int64? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.remoteURL = remoteURL
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct SpeechModelManifest: Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let backend: String
    public let artifacts: [SpeechModelArtifact]

    public init(id: String, version: String, backend: String, artifacts: [SpeechModelArtifact]) {
        self.id = id
        self.version = version
        self.backend = backend
        self.artifacts = artifacts
    }

    public var requiredRelativePaths: [String] {
        artifacts.map(\.relativePath)
    }
}

public protocol ModelManager: Sendable {
    func manifest(for modelID: String) -> SpeechModelManifest?
    func localDirectory(for modelID: String) -> URL
    func isInstalled(_ modelID: String) -> Bool
}
