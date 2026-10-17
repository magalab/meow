import Foundation
import MeowS3

final class S3Uploader: FileUploader, @unchecked Sendable {
    private let config: S3Config
    private let client: S3Client

    init(config: S3Config, secretAccessKey: String) throws {
        var normalizedConfig = config
        normalizedConfig.endpoint = Self.normalizedHTTPURLString(config.endpoint)
        normalizedConfig.publicBaseURL = Self.normalizedHTTPURLString(config.publicBaseURL)
        guard !normalizedConfig.accessKeyID.isEmpty, !secretAccessKey.isEmpty,
              !normalizedConfig.bucket.isEmpty, !normalizedConfig.region.isEmpty
        else { throw UploadError.notConfigured }
        if !normalizedConfig.endpoint.isEmpty { try Self.validateHTTPURL(normalizedConfig.endpoint) }
        if !normalizedConfig.publicBaseURL.isEmpty { try Self.validateHTTPURL(normalizedConfig.publicBaseURL) }
        self.config = normalizedConfig
        let endpoint = normalizedConfig.endpoint.isEmpty ? nil : URL(string: normalizedConfig.endpoint)
        let addressingStyle: S3AddressingStyle = normalizedConfig.urlStyle == .path ? .path : .virtualHosted
        client = try S3Client(configuration: .init(
            endpoint: endpoint,
            region: normalizedConfig.region,
            bucket: normalizedConfig.bucket,
            accessKeyID: normalizedConfig.accessKeyID,
            secretAccessKey: secretAccessKey,
            addressingStyle: addressingStyle
        ))
    }

    func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> UploadResult {
        do {
            try await client.upload(
                fileURL: request.fileURL,
                objectKey: request.objectKey,
                contentType: request.mimeType
            ) { value in
                progress(.init(sentBytes: value.sentBytes, totalBytes: value.totalBytes))
            }
            let publicURL = try await shareURL(for: request.objectKey)
            return UploadResult(
                objectKey: request.objectKey,
                shareURL: publicURL,
                fileSize: request.fileSize,
                mimeType: request.mimeType
            )
        } catch is CancellationError {
            throw UploadError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw UploadError.cancelled
        } catch let error as S3ClientError {
            throw Self.map(error)
        } catch {
            throw UploadError.s3Error(error.localizedDescription)
        }
    }

    func shareURL(for objectKey: String) async throws -> URL {
        switch config.publicURLStrategy {
        case .customDomain:
            guard let base = normalizedURL(config.publicBaseURL) else {
                throw UploadError.publicURLUnavailable
            }
            return try appendEncodedPath(ObjectKeyBuilder.encodedPath(objectKey), to: base)
        case .publicBucket:
            if let base = normalizedURL(config.publicBaseURL) {
                return try appendEncodedPath(ObjectKeyBuilder.encodedPath(objectKey), to: base)
            }
            return try apiURL(for: objectKey)
        }
    }

    func deleteObject(for objectKey: String) async throws {
        do {
            try await client.delete(objectKey: objectKey)
        } catch is CancellationError {
            throw UploadError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw UploadError.cancelled
        } catch let error as S3ClientError {
            throw Self.map(error)
        } catch {
            throw UploadError.s3Error(error.localizedDescription)
        }
    }

    func shutdown() async throws {
        await client.shutdown()
    }

    private static func map(_ error: S3ClientError) -> UploadError {
        switch error {
        case .invalidConfiguration: .notConfigured
        case .invalidEndpoint: .publicURLUnavailable
        case .invalidObjectKey: .invalidObjectKey
        case let .unreadableFile(filename): .fileUnreadable(filename)
        case .invalidResponse: .invalidResponse
        case let .service(_, message): .s3Error(message)
        }
    }

    private func apiURL(for objectKey: String) throws -> URL {
        let endpoint: URL
        if let configured = normalizedURL(config.endpoint) {
            endpoint = configured
        } else {
            let key = ObjectKeyBuilder.encodedPath(objectKey)
            let value = config.urlStyle == .virtualHosted && !config.bucket.contains(".")
                ? "https://\(config.bucket).s3.\(config.region).amazonaws.com/\(key)"
                : "https://s3.\(config.region).amazonaws.com/\(config.bucket)/\(key)"
            guard let url = URL(string: value) else { throw UploadError.publicURLUnavailable }
            return url
        }
        let useVirtualHost = config.urlStyle == .virtualHosted && !config.bucket.contains(".")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw UploadError.publicURLUnavailable
        }
        var prefix = components.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        if useVirtualHost, let host = components.host {
            components.host = "\(config.bucket).\(host)"
        }
        let key = ObjectKeyBuilder.encodedPath(objectKey)
        components.percentEncodedPath = prefix + (useVirtualHost ? "" : "/\(config.bucket)") + "/\(key)"
        guard let url = components.url else { throw UploadError.publicURLUnavailable }
        return url
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func appendEncodedPath(_ path: String, to base: URL) throws -> URL {
        let prefix = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard let result = URL(string: prefix + path) else { throw UploadError.publicURLUnavailable }
        return result
    }

    private static func validateHTTPURL(_ value: String) throws {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              components.query == nil,
              components.fragment == nil
        else { throw UploadError.publicURLUnavailable }
    }

    private static func normalizedHTTPURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return trimmed }
        return "https://\(trimmed)"
    }
}
