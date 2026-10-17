import CryptoKit
import Foundation

public enum S3AddressingStyle: Equatable, Sendable {
    case path
    case virtualHosted
}

public struct S3ClientConfiguration: Sendable {
    public let endpoint: URL?
    public let region: String
    public let bucket: String
    public let accessKeyID: String
    public let secretAccessKey: String
    public let addressingStyle: S3AddressingStyle

    public init(
        endpoint: URL? = nil,
        region: String,
        bucket: String,
        accessKeyID: String,
        secretAccessKey: String,
        addressingStyle: S3AddressingStyle = .virtualHosted
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.addressingStyle = addressingStyle
    }
}

public struct S3UploadProgress: Sendable, Equatable {
    public let sentBytes: Int64
    public let totalBytes: Int64

    public init(sentBytes: Int64, totalBytes: Int64) {
        self.sentBytes = sentBytes
        self.totalBytes = totalBytes
    }
}

public enum S3ClientError: LocalizedError, Sendable {
    case invalidConfiguration
    case invalidEndpoint
    case invalidObjectKey
    case unreadableFile(String)
    case invalidResponse
    case service(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "S3 credentials, region, and bucket are required."
        case .invalidEndpoint: "The S3 endpoint must be an HTTP or HTTPS URL without a query or fragment."
        case .invalidObjectKey: "The object key is empty or invalid."
        case let .unreadableFile(name): "The file could not be read: \(name)"
        case .invalidResponse: "The S3 service returned an invalid response."
        case let .service(statusCode, message): "S3 returned HTTP \(statusCode): \(message)"
        }
    }
}

/// Minimal S3 client for object upload and deletion. It uses AWS Signature V4
/// with signed payload hashes and supports single-request and multipart uploads.
public actor S3Client {
    public typealias ProgressHandler = @Sendable (S3UploadProgress) -> Void

    private static let multipartThreshold: Int64 = 64 * 1_024 * 1_024
    private static let multipartPartSize = 16 * 1_024 * 1_024
    private static let multipartConcurrency = 4
    private static let maximumRetries = 2

    private let configuration: S3ClientConfiguration
    private let transport: any S3HTTPTransport
    private let now: @Sendable () -> Date

    public init(configuration: S3ClientConfiguration) throws {
        try self.init(configuration: configuration, transport: URLSessionS3Transport(), now: Date.init)
    }

    init(
        configuration: S3ClientConfiguration,
        transport: any S3HTTPTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard !configuration.region.isEmpty,
              !configuration.bucket.isEmpty,
              !configuration.accessKeyID.isEmpty,
              !configuration.secretAccessKey.isEmpty
        else { throw S3ClientError.invalidConfiguration }
        if let endpoint = configuration.endpoint {
            guard let scheme = endpoint.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  endpoint.host != nil,
                  endpoint.query == nil,
                  endpoint.fragment == nil,
                  endpoint.user == nil,
                  endpoint.password == nil
            else { throw S3ClientError.invalidEndpoint }
        }
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    public func upload(
        fileURL: URL,
        objectKey: String,
        contentType: String,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws {
        guard Self.isValidObjectKey(objectKey) else {
            throw S3ClientError.invalidObjectKey
        }
        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw S3ClientError.unreadableFile(fileURL.lastPathComponent)
        }
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw S3ClientError.unreadableFile(fileURL.lastPathComponent)
        }
        try Task.checkCancellation()
        if Int64(size) >= Self.multipartThreshold {
            try await multipartUpload(
                fileURL: fileURL,
                objectKey: objectKey,
                contentType: contentType,
                fileSize: Int64(size),
                progress: progress
            )
        } else {
            let payloadHash = try Self.sha256(fileURL: fileURL)
            let request = try signedRequest(
                method: "PUT",
                objectKey: objectKey,
                query: [],
                contentType: contentType,
                payloadHash: payloadHash,
                contentLength: Int64(size)
            )
            let response = try await sendWithRetry(request, fileURL: fileURL, progress: { sent in
                progress(.init(sentBytes: min(Int64(size), sent), totalBytes: Int64(size)))
            })
            try Self.validate(response)
            progress(.init(sentBytes: Int64(size), totalBytes: Int64(size)))
        }
    }

    public func delete(objectKey: String) async throws {
        guard Self.isValidObjectKey(objectKey) else {
            throw S3ClientError.invalidObjectKey
        }
        let request = try signedRequest(
            method: "DELETE",
            objectKey: objectKey,
            query: [],
            contentType: nil,
            payloadHash: Self.emptyPayloadHash,
            contentLength: 0
        )
        let response = try await sendWithRetry(request, data: Data(), progress: nil)
        try Self.validate(response)
    }

    public func shutdown() async {
        await transport.shutdown()
    }

    private func multipartUpload(
        fileURL: URL,
        objectKey: String,
        contentType: String,
        fileSize: Int64,
        progress: @escaping ProgressHandler
    ) async throws {
        let createRequest = try signedRequest(
            method: "POST",
            objectKey: objectKey,
            query: [("uploads", "")],
            contentType: contentType,
            payloadHash: Self.emptyPayloadHash,
            contentLength: 0
        )
        let createResponse = try await sendWithRetry(createRequest, data: Data(), progress: nil, retryable: false)
        try Self.validate(createResponse)
        guard let uploadID = Self.xmlValue(named: "UploadId", in: createResponse.data), !uploadID.isEmpty else {
            throw S3ClientError.invalidResponse
        }

        var completedParts: [(number: Int, etag: String)] = []
        let transferProgress = MultipartTransferProgress(totalBytes: fileSize, callback: progress)
        var nextPartNumber = 1
        let partCount = Int((fileSize + Int64(Self.multipartPartSize) - 1) / Int64(Self.multipartPartSize))
        do {
            let file: FileHandle
            do { file = try FileHandle(forReadingFrom: fileURL) }
            catch { throw S3ClientError.unreadableFile(fileURL.lastPathComponent) }
            defer { try? file.close() }
            try await withThrowingTaskGroup(of: (Int, String, Int64).self) { group in
                while nextPartNumber <= min(partCount, Self.multipartConcurrency) {
                    try Task.checkCancellation()
                    let partNumber = nextPartNumber
                    nextPartNumber += 1
                    let chunk = try Self.readPart(
                        file,
                        partNumber: partNumber,
                        fileSize: fileSize,
                        fileURL: fileURL
                    )
                    let request = try signedRequest(
                        method: "PUT",
                        objectKey: objectKey,
                        query: [("partNumber", String(partNumber)), ("uploadId", uploadID)],
                        contentType: nil,
                        payloadHash: Self.sha256(chunk),
                        contentLength: Int64(chunk.count)
                    )
                    group.addTask {
                        try await self.uploadPart(
                            request,
                            chunk: chunk,
                            partNumber: partNumber,
                            transferProgress: transferProgress
                        )
                    }
                }

                while let part = try await group.next() {
                    completedParts.append((part.0, part.1))
                    transferProgress.complete(part: part.0, bytes: part.2)
                    guard nextPartNumber <= partCount else { continue }
                    try Task.checkCancellation()
                    let partNumber = nextPartNumber
                    nextPartNumber += 1
                    let chunk = try Self.readPart(
                        file,
                        partNumber: partNumber,
                        fileSize: fileSize,
                        fileURL: fileURL
                    )
                    let request = try signedRequest(
                        method: "PUT",
                        objectKey: objectKey,
                        query: [("partNumber", String(partNumber)), ("uploadId", uploadID)],
                        contentType: nil,
                        payloadHash: Self.sha256(chunk),
                        contentLength: Int64(chunk.count)
                    )
                    group.addTask {
                        try await self.uploadPart(
                            request,
                            chunk: chunk,
                            partNumber: partNumber,
                            transferProgress: transferProgress
                        )
                    }
                }
            }
            completedParts.sort { $0.number < $1.number }
            let xml = Self.completionXML(parts: completedParts)
            let completeRequest = try signedRequest(
                method: "POST",
                objectKey: objectKey,
                query: [("uploadId", uploadID)],
                contentType: "application/xml",
                payloadHash: Self.sha256(xml),
                contentLength: Int64(xml.count)
            )
            let completeResponse = try await sendWithRetry(
                completeRequest,
                data: xml,
                progress: nil,
                retryable: false
            )
            try Self.validate(completeResponse)
            if let errorCode = Self.xmlValue(named: "Code", in: completeResponse.data) {
                let message = Self.xmlValue(named: "Message", in: completeResponse.data) ?? errorCode
                throw S3ClientError.service(statusCode: completeResponse.statusCode, message: message)
            }
            progress(.init(sentBytes: fileSize, totalBytes: fileSize))
        } catch {
            await abortMultipart(objectKey: objectKey, uploadID: uploadID)
            throw error
        }
    }

    private func uploadPart(
        _ request: URLRequest,
        chunk: Data,
        partNumber: Int,
        transferProgress: MultipartTransferProgress
    ) async throws -> (Int, String, Int64) {
        let response = try await sendWithRetry(request, data: chunk) { sent in
            transferProgress.report(part: partNumber, sentBytes: sent)
        }
        try Self.validate(response)
        guard let etag = response.header("ETag") else { throw S3ClientError.invalidResponse }
        return (partNumber, etag, Int64(chunk.count))
    }

    private func abortMultipart(objectKey: String, uploadID: String) async {
        guard let request = try? signedRequest(
            method: "DELETE",
            objectKey: objectKey,
            query: [("uploadId", uploadID)],
            contentType: nil,
            payloadHash: Self.emptyPayloadHash,
            contentLength: 0
        ) else { return }
        _ = try? await Task.detached {
            try await self.sendWithRetry(request, data: Data(), progress: nil)
        }.value
    }

    private func sendWithRetry(
        _ request: URLRequest,
        fileURL: URL? = nil,
        data: Data? = nil,
        progress: (@Sendable (Int64) -> Void)?,
        retryable: Bool = true
    ) async throws -> S3HTTPResponse {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let response = try await transport.send(request, fileURL: fileURL, data: data, progress: progress)
                if retryable, Self.isRetryable(statusCode: response.statusCode), attempt < Self.maximumRetries {
                    try await Self.delay(attempt: attempt)
                    attempt += 1
                    continue
                }
                return response
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError where Self.isRetryable(error: error) && attempt < Self.maximumRetries && retryable {
                try await Self.delay(attempt: attempt)
                attempt += 1
            }
        }
    }

    private func signedRequest(
        method: String,
        objectKey: String,
        query: [(String, String)],
        contentType: String?,
        payloadHash: String,
        contentLength: Int64
    ) throws -> URLRequest {
        let url = try Self.objectURL(configuration: configuration, objectKey: objectKey, query: query)
        let timestamp = Self.timestamp(now())
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")
        var headers = [
            "host": Self.canonicalHost(url),
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": timestamp,
        ]
        if let contentType { headers["content-type"] = contentType }
        let authorization = S3V4Signer.authorization(
            accessKeyID: configuration.accessKeyID,
            secretAccessKey: configuration.secretAccessKey,
            region: configuration.region,
            method: method,
            url: url,
            canonicalQuery: Self.canonicalQuery(query),
            headers: headers,
            payloadHash: payloadHash,
            timestamp: timestamp
        )
        request.setValue(
            authorization,
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    static func objectURL(
        configuration: S3ClientConfiguration,
        objectKey: String,
        query: [(String, String)] = []
    ) throws -> URL {
        let endpoint: URL
        if let configured = configuration.endpoint {
            endpoint = configured
        } else {
            let host: String
            if configuration.addressingStyle == .virtualHosted,
               !configuration.bucket.contains(".")
            {
                host = "\(configuration.bucket).s3.\(configuration.region).amazonaws.com"
            } else {
                host = "s3.\(configuration.region).amazonaws.com"
            }
            guard let value = URL(string: "https://\(host)") else { throw S3ClientError.invalidEndpoint }
            endpoint = value
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let endpointHost = components.host
        else { throw S3ClientError.invalidEndpoint }
        let useVirtualHost = configuration.addressingStyle == .virtualHosted
            && !configuration.bucket.contains(".")
        if useVirtualHost {
            components.host = "\(configuration.bucket).\(endpointHost)"
        }
        var prefix = components.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        let encodedKey = objectKey.split(separator: "/", omittingEmptySubsequences: false)
            .map { percentEncode(String($0)) }
            .joined(separator: "/")
        let bucketPath = useVirtualHost ? "" : "/\(percentEncode(configuration.bucket))"
        components.percentEncodedPath = prefix + bucketPath + "/" + encodedKey
        let queryString = canonicalQuery(query)
        components.percentEncodedQuery = queryString.isEmpty ? nil : queryString
        guard let url = components.url else { throw S3ClientError.invalidEndpoint }
        return url
    }

    static func canonicalQuery(_ query: [(String, String)]) -> String {
        var encoded: [(key: String, value: String)] = []
        for (key, value) in query {
            encoded.append((percentEncode(key), percentEncode(value)))
        }
        encoded.sort { lhs, rhs in
            if lhs.key == rhs.key { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }
        return encoded.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }

    static func canonicalURI(_ url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return path.isEmpty ? "/" : path
    }

    static func canonicalHost(_ url: URL) -> String {
        guard let host = url.host else { return "" }
        guard let port = url.port,
              !((url.scheme == "https" && port == 443) || (url.scheme == "http" && port == 80))
        else { return host.lowercased() }
        return "\(host.lowercased()):\(port)"
    }

    static func signingKey(secret: String, date: String, region: String) -> Data {
        let dateKey = hmac(key: Data(("AWS4" + secret).utf8), data: Data(date.utf8))
        let regionKey = hmac(key: dateKey, data: Data(region.utf8))
        let serviceKey = hmac(key: regionKey, data: Data("s3".utf8))
        return hmac(key: serviceKey, data: Data("aws4_request".utf8))
    }

    static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    static func sha256(_ data: Data) -> String {
        hex(Data(SHA256.hash(data: data)))
    }

    static func sha256(fileURL: URL) throws -> String {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: fileURL) }
        catch { throw S3ClientError.unreadableFile(fileURL.lastPathComponent) }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hex(Data(hasher.finalize()))
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    static func percentEncode(_ value: String) -> String {
        value.utf8.map { byte in
            if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 || byte == 95 || byte == 126
            { return String(UnicodeScalar(byte)) }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private static var emptyPayloadHash: String { sha256(Data()) }

    private static func isValidObjectKey(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 1_024
    }

    private static func readPart(
        _ file: FileHandle,
        partNumber: Int,
        fileSize: Int64,
        fileURL: URL
    ) throws -> Data {
        let offset = Int64(partNumber - 1) * Int64(multipartPartSize)
        let expectedSize = Int(min(Int64(multipartPartSize), fileSize - offset))
        var data = Data()
        data.reserveCapacity(expectedSize)
        while data.count < expectedSize {
            guard let chunk = try file.read(upToCount: expectedSize - data.count), !chunk.isEmpty else {
                throw S3ClientError.unreadableFile(fileURL.lastPathComponent)
            }
            data.append(chunk)
        }
        return data
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func completionXML(parts: [(number: Int, etag: String)]) -> Data {
        let entries = parts.map { part in
            "<Part><PartNumber>\(part.number)</PartNumber><ETag>\(xmlEscape(part.etag))</ETag></Part>"
        }.joined()
        return Data("<CompleteMultipartUpload>\(entries)</CompleteMultipartUpload>".utf8)
    }

    private static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func xmlValue(named name: String, in data: Data) -> String? {
        guard let body = String(data: data, encoding: .utf8),
              let start = body.range(of: "<\(name)>")?.upperBound,
              let end = body.range(of: "</\(name)>", range: start..<body.endIndex)?.lowerBound
        else { return nil }
        return String(body[start..<end])
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func validate(_ response: S3HTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let code = xmlValue(named: "Code", in: response.data)
            let detail = xmlValue(named: "Message", in: response.data)
                ?? String(data: response.data.prefix(512), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            let message = code.map { "\($0): \(detail)" } ?? detail
            throw S3ClientError.service(statusCode: response.statusCode, message: message)
        }
    }

    private static func isRetryable(error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
             .resourceUnavailable, .timedOut, .cannotFindHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private static func isRetryable(statusCode: Int) -> Bool {
        [429, 500, 502, 503, 504].contains(statusCode)
    }

    private static func delay(attempt: Int) async throws {
        try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
    }
}

struct S3V4Signer {
    static func authorization(
        accessKeyID: String,
        secretAccessKey: String,
        region: String,
        method: String,
        url: URL,
        canonicalQuery: String,
        headers: [String: String],
        payloadHash: String,
        timestamp: String
    ) -> String {
        let normalizedHeaders = headers
            .map { ($0.key.lowercased(), normalize($0.value)) }
            .sorted { $0.0 < $1.0 }
        let signedHeaders = normalizedHeaders.map(\.0).joined(separator: ";")
        let canonicalHeaders = normalizedHeaders.map { "\($0.0):\($0.1)" }.joined(separator: "\n") + "\n"
        let canonicalRequest = [
            method,
            S3Client.canonicalURI(url),
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
        let date = String(timestamp.prefix(8))
        let scope = "\(date)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp,
            scope,
            S3Client.sha256(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let key = S3Client.signingKey(secret: secretAccessKey, date: date, region: region)
        let signature = S3Client.hex(S3Client.hmac(key: key, data: Data(stringToSign.utf8)))
        return "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope),SignedHeaders=\(signedHeaders),Signature=\(signature)"
    }

    private static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct S3HTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

protocol S3HTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        fileURL: URL?,
        data: Data?,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws -> S3HTTPResponse
    func shutdown() async
}

extension S3HTTPTransport {
    func shutdown() async {}
}

private final class URLSessionS3Transport: NSObject, S3HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private struct PendingTransfer {
        let continuation: CheckedContinuation<S3HTTPResponse, Error>
        let progress: (@Sendable (Int64) -> Void)?
    }

    private let lock = NSLock()
    private var transfers: [Int: PendingTransfer] = [:]
    private var session: URLSession!

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func shutdown() async {
        session.invalidateAndCancel()
    }

    func send(
        _ request: URLRequest,
        fileURL: URL?,
        data: Data?,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws -> S3HTTPResponse {
        let cancellation = TransferCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let context = TransferContext()
                let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = { [weak self, context] data, response, error in
                    guard let self else { return }
                    let taskID = context.taskID
                    if let error {
                        self.finish(taskID: taskID, result: .failure(error))
                        return
                    }
                    guard let response = response as? HTTPURLResponse else {
                        self.finish(taskID: taskID, result: .failure(S3ClientError.invalidResponse))
                        return
                    }
                    var headers: [String: String] = [:]
                    for (key, value) in response.allHeaderFields {
                        if let key = key as? String { headers[key] = String(describing: value) }
                    }
                    self.finish(taskID: taskID, result: .success(.init(
                        statusCode: response.statusCode,
                        data: data ?? Data(),
                        headers: headers
                    )))
                }
                let task: URLSessionUploadTask
                if let fileURL {
                    task = session.uploadTask(with: request, fromFile: fileURL, completionHandler: completion)
                } else {
                    task = session.uploadTask(with: request, from: data ?? Data(), completionHandler: completion)
                }
                let taskID = task.taskIdentifier
                context.taskID = taskID
                lock.withLock { transfers[taskID] = PendingTransfer(continuation: continuation, progress: progress) }
                cancellation.setTask(task)
                task.resume()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let callback = lock.withLock { transfers[task.taskIdentifier]?.progress }
        callback?(totalBytesSent)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func finish(taskID: Int, result: Result<S3HTTPResponse, Error>) {
        let pending = lock.withLock { transfers.removeValue(forKey: taskID) }
        guard let pending else { return }
        pending.continuation.resume(with: result)
    }
}

private final class TransferContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTaskID = 0
    var taskID: Int {
        get { lock.withLock { storedTaskID } }
        set { lock.withLock { storedTaskID = newValue } }
    }
}

private final class TransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func setTask(_ task: URLSessionTask) {
        let cancelNow = lock.withLock {
            self.task = task
            return isCancelled
        }
        if cancelNow { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }
}

private final class MultipartTransferProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let totalBytes: Int64
    private let callback: S3Client.ProgressHandler
    private var acknowledged: Int64 = 0
    private var inFlight: [Int: Int64] = [:]

    init(totalBytes: Int64, callback: @escaping S3Client.ProgressHandler) {
        self.totalBytes = totalBytes
        self.callback = callback
    }

    func report(part: Int, sentBytes: Int64) {
        let sent = lock.withLock { () -> Int64 in
            inFlight[part] = max(inFlight[part] ?? 0, sentBytes)
            return min(totalBytes, acknowledged + inFlight.values.reduce(0, +))
        }
        callback(.init(sentBytes: sent, totalBytes: totalBytes))
    }

    func complete(part: Int, bytes: Int64) {
        let sent = lock.withLock { () -> Int64 in
            inFlight.removeValue(forKey: part)
            acknowledged += bytes
            return min(totalBytes, acknowledged + inFlight.values.reduce(0, +))
        }
        callback(.init(sentBytes: sent, totalBytes: totalBytes))
    }
}
