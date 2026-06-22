import Foundation
import SotoS3

final class S3Uploader: FileUploader, @unchecked Sendable {
    private static let multipartThreshold: Int64 = 64 * 1_024 * 1_024
    private static let partSize = 16 * 1_024 * 1_024

    private let config: S3Config
    private let client: AWSClient
    private let s3: S3

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
        client = AWSClient(
            credentialProvider: .static(
                accessKeyId: config.accessKeyID,
                secretAccessKey: secretAccessKey
            )
        )
        let options = Self.serviceOptions(for: normalizedConfig)
        s3 = S3(
            client: client,
            region: Region(rawValue: normalizedConfig.region),
            endpoint: normalizedConfig.endpoint.isEmpty ? nil : normalizedConfig.endpoint,
            options: options
        )
    }

    static func serviceOptions(for config: S3Config) -> AWSServiceConfig.Options {
        var options: AWSServiceConfig.Options = []
        if config.urlStyle == .virtualHosted {
            options.insert(.s3ForceVirtualHost)
        }
        let endpointHost = URLComponents(string: config.endpoint)?.host?.lowercased() ?? ""
        if config.region.lowercased() == "auto" || endpointHost.hasSuffix(".r2.cloudflarestorage.com") {
            options.insert(.s3DisableChunkedUploads)
        }
        return options
    }

    func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> UploadResult {
        do {
            try Task.checkCancellation()
            if request.fileSize >= Self.multipartThreshold {
                try await multipartUpload(request, progress: progress)
            } else {
                let sequence = FileChunkSequence(
                    url: request.fileURL,
                    chunkSize: 1 * 1_024 * 1_024,
                    total: request.fileSize,
                    progress: progress
                )
                let body = AWSHTTPBody(asyncSequence: sequence, length: Int(request.fileSize))
                let input = S3.PutObjectRequest(
                    body: body,
                    bucket: config.bucket,
                    contentLength: request.fileSize,
                    contentType: request.mimeType,
                    key: request.objectKey
                )
                _ = try await s3.putObject(input)
            }
            return UploadResult(
                objectKey: request.objectKey,
                shareURL: try await shareURL(for: request.objectKey),
                fileSize: request.fileSize,
                mimeType: request.mimeType
            )
        } catch is CancellationError {
            throw UploadError.cancelled
        } catch let error as UploadError {
            throw error
        } catch {
            throw UploadError.s3Error(Self.errorMessage(for: error))
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
        case .presigned:
            return try await s3.signURL(
                url: apiURL(for: objectKey),
                httpMethod: .GET,
                expires: .seconds(Int64(max(1, min(config.presignedURLExpiration, 604_800))))
            )
        }
    }

    func deleteObject(for objectKey: String) async throws {
        do {
            _ = try await s3.deleteObject(.init(bucket: config.bucket, key: objectKey))
        } catch is CancellationError {
            throw UploadError.cancelled
        } catch {
            throw UploadError.s3Error(Self.errorMessage(for: error))
        }
    }

    static func errorMessage(for error: Error) -> String {
        if let awsError = error as? any AWSErrorType {
            var heading = awsError.errorCode
            if let statusCode = awsError.context?.responseCode.code {
                heading = "HTTP \(statusCode) · \(heading)"
            }
            let message = awsError.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return "\(heading): \(message)"
            }
            return heading
        }
        if let rawError = error as? AWSRawError {
            return rawError.description
        }
        return error.localizedDescription
    }

    func shutdown() async throws {
        try await client.shutdown()
    }

    private func multipartUpload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws {
        _ = try await s3.multipartUpload(
            .init(
                bucket: config.bucket,
                contentType: request.mimeType,
                key: request.objectKey
            ),
            partSize: Self.partSize,
            filename: request.fileURL.path,
            concurrentUploads: 4,
            abortOnFail: true
        ) { fraction in
            try Task.checkCancellation()
            let sent = min(request.fileSize, Int64(Double(request.fileSize) * fraction))
            progress(.init(sentBytes: sent, totalBytes: request.fileSize))
        }
    }

    private func apiURL(for objectKey: String) throws -> URL {
        let key = ObjectKeyBuilder.encodedPath(objectKey)
        if !config.endpoint.isEmpty, let endpoint = normalizedURL(config.endpoint) {
            if config.urlStyle == .virtualHosted,
               !config.bucket.contains("."),
               var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
               let host = components.host
            {
                components.host = "\(config.bucket).\(host)"
                guard let base = components.url else { throw UploadError.publicURLUnavailable }
                return try appendEncodedPath(key, to: base)
            }
            return try appendEncodedPath("\(config.bucket)/\(key)", to: endpoint)
        }
        let value = config.urlStyle == .virtualHosted && !config.bucket.contains(".")
            ? "https://\(config.bucket).s3.\(config.region).amazonaws.com/\(key)"
            : "https://s3.\(config.region).amazonaws.com/\(config.bucket)/\(key)"
        guard let url = URL(string: value) else {
            throw UploadError.publicURLUnavailable
        }
        return url
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

struct FileChunkSequence: AsyncSequence, Sendable {
    typealias Element = Data

    let url: URL
    let chunkSize: Int
    let total: Int64
    let progress: @Sendable (UploadProgress) -> Void

    func makeAsyncIterator() -> Iterator {
        Iterator(url: url, chunkSize: chunkSize, total: total, progress: progress)
    }

    final class Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        private let chunkSize: Int
        private let total: Int64
        private let progress: @Sendable (UploadProgress) -> Void
        private let filename: String
        private var handle: FileHandle?
        private var isFinished = false
        private var sent: Int64 = 0

        init(url: URL, chunkSize: Int, total: Int64, progress: @escaping @Sendable (UploadProgress) -> Void) {
            self.chunkSize = chunkSize
            self.total = total
            self.progress = progress
            filename = url.lastPathComponent
            do {
                handle = try FileHandle(forReadingFrom: url)
            } catch {
                handle = nil
            }
        }

        func next() async throws -> Data? {
            try Task.checkCancellation()
            if isFinished { return nil }
            guard let handle else {
                throw UploadError.fileUnreadable(filename)
            }
            guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else {
                try? handle.close()
                self.handle = nil
                isFinished = true
                return nil
            }
            sent += Int64(data.count)
            progress(.init(sentBytes: sent, totalBytes: total))
            return data
        }
    }
}
