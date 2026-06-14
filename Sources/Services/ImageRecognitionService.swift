import Foundation
import Vision

enum ImageRecognitionError: LocalizedError {
    case imageUnavailable
    case noText
    case noQRCode

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: return L10n.screenshotOCRImageUnavailable
        case .noText: return L10n.screenshotOCRNoText
        case .noQRCode: return L10n.screenshotQRNotFound
        }
    }
}

final class ImageRecognitionService: Sendable {
    func recognizeText(
        in imageContent: ImageClipboardContent,
        languages: [String] = ["zh-Hans", "en-US"]
    ) async throws -> String {
        let path = imageContent.originalPath ?? imageContent.thumbnailPath
        return try await Task.detached(priority: .userInitiated) {
            try Self.recognizeText(at: URL(fileURLWithPath: path), languages: languages)
        }.value
    }

    func detectQRCode(in imageContent: ImageClipboardContent) async throws -> String {
        let path = imageContent.originalPath ?? imageContent.thumbnailPath
        return try await Task.detached(priority: .userInitiated) {
            try Self.detectQRCode(at: URL(fileURLWithPath: path))
        }.value
    }

    func sensitiveContentRects(in image: CGImage) async throws -> [CGRect] {
        try await Task.detached(priority: .userInitiated) {
            try Self.detectSensitiveContent(in: image)
        }.value
    }

    private static func recognizeText(at url: URL, languages: [String]) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageRecognitionError.imageUnavailable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages.isEmpty ? ["zh-Hans", "en-US"] : languages

        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ImageRecognitionError.noText
        }
        return text
    }

    private static func detectQRCode(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageRecognitionError.imageUnavailable
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])

        guard let payload = request.results?.first?.payloadStringValue,
              !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ImageRecognitionError.noQRCode
        }
        return payload
    }

    private static func detectSensitiveContent(in image: CGImage) throws -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let imageSize = CGSize(width: image.width, height: image.height)

        return (request.results ?? []).compactMap { observation -> CGRect? in
            guard let text = observation.topCandidates(1).first?.string,
                  isSensitiveText(text)
            else { return nil }
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX * imageSize.width,
                y: box.minY * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            return rect.insetBy(dx: -4, dy: -4)
                .intersection(CGRect(origin: .zero, size: imageSize))
        }
    }

    static func isSensitiveText(_ text: String) -> Bool {
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?:\+?\d[\d\s()\-]{7,}\d)"#,
            #"(?i)(?:api[_-]?key|secret|token|password|bearer)\s*[:=]?\s*\S+"#,
            #"(?i)\bsk-[A-Za-z0-9_-]{12,}\b"#,
        ]
        let expressions = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
        let range = NSRange(text.startIndex..., in: text)
        return expressions.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
