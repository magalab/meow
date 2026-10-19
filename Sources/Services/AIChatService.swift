import AppKit
import Foundation
import MeowAI

extension AIChatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.aiErrorNotConfigured
        case .invalidEndpoint:
            L10n.aiErrorInvalidEndpoint
        case .emptyResponse:
            L10n.aiErrorEmptyResponse
        case .imageUnavailable:
            L10n.aiErrorImageUnavailable
        case .visionUnsupported:
            L10n.aiErrorVisionUnsupported
        case let .requestFailed(statusCode):
            L10n.aiErrorRequestFailed(statusCode: statusCode)
        }
    }
}

struct AIChatService: Sendable {
    private var client: AIChatClient {
        AIChatClient(
            imageDataURLProvider: Self.imageDataURL,
            httpFailureLogger: Self.logHTTPFailure
        )
    }

    func fetchModels(settings: AISettings) async throws -> [String] {
        try await client.fetchModels(settings: settings)
    }

    func send(messages: [AIChatMessage], settings: AISettings) async throws -> String {
        try await client.send(messages: messages, settings: settings)
    }

    func requestBody(messages: [AIChatMessage], settings: AISettings) throws -> Data {
        try client.requestBody(messages: messages, settings: settings)
    }

    func normalizedEndpoint(_ rawValue: String) throws -> URL {
        try client.normalizedEndpoint(rawValue)
    }

    private static func imageDataURL(for path: String, settings: AISettings) throws -> String {
        guard let image = NSImage(contentsOfFile: path) else {
            throw AIChatError.imageUnavailable
        }

        let maxDimension = CGFloat(min(max(settings.imageMaxDimension, 512), 4_096))
        let sourceSize = image.size
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let prepared = scale < 1
            ? image.resized(
                to: NSSize(
                    width: max(1, sourceSize.width * scale),
                    height: max(1, sourceSize.height * scale)
                )
            )
            : image
        guard let cgImage = prepared.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AIChatError.imageUnavailable
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let quality = min(max(settings.imageJPEGQuality, 0.4), 1)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw AIChatError.imageUnavailable
        }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func logHTTPFailure(operation: String, detail: String, statusCode: Int) {
        MeowLog.ai.error(
            "\(operation, privacy: .public) failed with status \(statusCode, privacy: .public): \(detail, privacy: .private(mask: .hash))"
        )
    }
}
