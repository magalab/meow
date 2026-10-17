import Foundation
import Testing
@testable import MeowS3

private actor RecordingTransport: S3HTTPTransport {
    let failPartNumber: Int?
    private(set) var requests: [URLRequest] = []
    private(set) var payloadSizes: [Int] = []

    init(failPartNumber: Int? = nil) {
        self.failPartNumber = failPartNumber
    }

    func send(
        _ request: URLRequest,
        fileURL: URL?,
        data: Data?,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws -> S3HTTPResponse {
        requests.append(request)
        payloadSizes.append(data?.count ?? 0)
        if let data, let progress { progress(Int64(data.count)) }
        if request.httpMethod == "POST", request.url?.query == "uploads=" {
            return .init(statusCode: 200, data: Data("<InitiateMultipartUploadResult><UploadId>upload-1</UploadId></InitiateMultipartUploadResult>".utf8), headers: [:])
        }
        if request.httpMethod == "PUT", request.url?.query?.contains("partNumber=") == true {
            let number = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "partNumber" })?.value ?? "0"
            if Int(number) == failPartNumber {
                return .init(statusCode: 403, data: Data("<Error><Code>AccessDenied</Code><Message>denied</Message></Error>".utf8), headers: [:])
            }
            return .init(statusCode: 200, data: Data(), headers: ["ETag": "\"etag-\(number)\""])
        }
        if request.httpMethod == "POST" {
            return .init(statusCode: 200, data: Data("<CompleteMultipartUploadResult/>".utf8), headers: [:])
        }
        return .init(statusCode: 204, data: Data(), headers: [:])
    }

    func recordedRequests() -> [URLRequest] { requests }
}

private actor DelayedTransport: S3HTTPTransport {
    func send(
        _ request: URLRequest,
        fileURL: URL?,
        data: Data?,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws -> S3HTTPResponse {
        try await Task.sleep(for: .seconds(30))
        return .init(statusCode: 200, data: Data(), headers: [:])
    }
}

private actor RetryingTransport: S3HTTPTransport {
    private(set) var putAttempts = 0

    func send(
        _ request: URLRequest,
        fileURL: URL?,
        data: Data?,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws -> S3HTTPResponse {
        if request.httpMethod == "PUT" {
            putAttempts += 1
            if putAttempts == 1 { throw URLError(.timedOut) }
        }
        return .init(statusCode: 200, data: Data(), headers: [:])
    }
}

private func makeConfiguration(
    endpoint: URL? = URL(string: "https://s3.amazonaws.com"),
    style: S3AddressingStyle = .virtualHosted
) -> S3ClientConfiguration {
    .init(
        endpoint: endpoint,
        region: "us-east-1",
        bucket: "examplebucket",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        addressingStyle: style
    )
}

@Test("S3 SigV4 matches the official AWS GET Object example")
func sigV4OfficialExample() throws {
    let url = try #require(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt"))
    let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    let authorization = S3V4Signer.authorization(
        accessKeyID: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        method: "GET",
        url: url,
        canonicalQuery: "",
        headers: [
            "host": "examplebucket.s3.amazonaws.com",
            "range": "bytes=0-9",
            "x-amz-content-sha256": emptyHash,
            "x-amz-date": "20130524T000000Z",
        ],
        payloadHash: emptyHash,
        timestamp: "20130524T000000Z"
    )
    #expect(authorization == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
}

@Test("S3 object URLs preserve slashes and encode UTF-8 key bytes")
func objectURLPathAndVirtualHostedStyles() throws {
    let virtual = try S3Client.objectURL(
        configuration: makeConfiguration(),
        objectKey: "目录/a #&.txt"
    )
    #expect(virtual.absoluteString == "https://examplebucket.s3.amazonaws.com/%E7%9B%AE%E5%BD%95/a%20%23%26.txt")

    let path = try S3Client.objectURL(
        configuration: makeConfiguration(style: .path),
        objectKey: "a//b.txt"
    )
    #expect(path.absoluteString == "https://s3.amazonaws.com/examplebucket/a//b.txt")
}

@Test("S3 canonical query encodes and sorts multipart parameters")
func canonicalMultipartQuery() {
    #expect(S3Client.canonicalQuery([("uploadId", "id +/"), ("partNumber", "2")]) == "partNumber=2&uploadId=id%20%2B%2F")
    #expect(S3Client.canonicalQuery([("uploads", "")]) == "uploads=")
}

@Test("R2 and MinIO endpoint URL styles retain endpoint prefixes and ports")
func compatibleProviderEndpoints() throws {
    let r2 = S3ClientConfiguration(
        endpoint: URL(string: "https://account.r2.cloudflarestorage.com")!,
        region: "auto",
        bucket: "uploads",
        accessKeyID: "key",
        secretAccessKey: "secret",
        addressingStyle: .path
    )
    let r2URL = try S3Client.objectURL(configuration: r2, objectKey: "folder/file.txt")
    #expect(r2URL.absoluteString == "https://account.r2.cloudflarestorage.com/uploads/folder/file.txt")

    let minio = S3ClientConfiguration(
        endpoint: URL(string: "http://localhost:9000/minio/")!,
        region: "us-east-1",
        bucket: "uploads",
        accessKeyID: "key",
        secretAccessKey: "secret",
        addressingStyle: .path
    )
    let minioURL = try S3Client.objectURL(configuration: minio, objectKey: "folder/file.txt")
    #expect(minioURL.absoluteString == "http://localhost:9000/minio/uploads/folder/file.txt")
}

@Test("Single PUT and DELETE are signed and use configured endpoint style")
func signedPutAndDelete() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("hello.txt")
    try Data("hello".utf8).write(to: file)
    let transport = RecordingTransport()
    let client = try S3Client(
        configuration: makeConfiguration(),
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_369_368_000) }
    )

    try await client.upload(fileURL: file, objectKey: "folder/hello.txt", contentType: "text/plain")
    try await client.delete(objectKey: "folder/hello.txt")
    let requests = await transport.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[0].httpMethod == "PUT")
    #expect(requests[0].url?.absoluteString == "https://examplebucket.s3.amazonaws.com/folder/hello.txt")
    #expect(requests[0].value(forHTTPHeaderField: "x-amz-content-sha256") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization")?.contains("SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date") == true)
    #expect(requests[1].httpMethod == "DELETE")
}

@Test("Multipart upload creates parts, completes, and reports progress")
func multipartUploadLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("large.bin")
    _ = FileManager.default.createFile(atPath: file.path, contents: Data())
    let handle = try FileHandle(forWritingTo: file)
    let expectedSize: Int64 = 64 * 1_024 * 1_024 + 3
    try handle.truncate(atOffset: UInt64(expectedSize))
    try handle.close()

    let transport = RecordingTransport()
    let client = try S3Client(configuration: makeConfiguration(), transport: transport)
    let progress = ProgressRecorder()
    try await client.upload(fileURL: file, objectKey: "large.bin", contentType: "application/octet-stream") { value in
        progress.record(value.sentBytes)
    }
    let requests = await transport.recordedRequests()
    #expect(requests.first?.url?.query == "uploads=")
    #expect(requests.filter { $0.httpMethod == "PUT" }.count == 5)
    #expect(requests.last?.httpMethod == "POST")
    #expect(requests.last?.url?.query?.hasPrefix("uploadId=") == true)
    #expect(progress.maximum == expectedSize)
}

@Test("Multipart failure aborts the incomplete upload")
func multipartFailureAborts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("large.bin")
    _ = FileManager.default.createFile(atPath: file.path, contents: Data())
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 64 * 1_024 * 1_024)
    try handle.close()

    let transport = RecordingTransport(failPartNumber: 2)
    let client = try S3Client(configuration: makeConfiguration(), transport: transport)
    do {
        try await client.upload(fileURL: file, objectKey: "large.bin", contentType: "application/octet-stream")
        Issue.record("Expected the multipart upload to fail")
    } catch let error as S3ClientError {
        #expect(error.localizedDescription.contains("AccessDenied"))
    }
    let requests = await transport.recordedRequests()
    #expect(requests.contains { $0.httpMethod == "DELETE" && $0.url?.query?.contains("uploadId=upload-1") == true })
    #expect(requests.filter { $0.httpMethod == "POST" }.count == 1)
}

@Test("Cancelling a request interrupts the transport")
func uploadCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("hello.txt")
    try Data("hello".utf8).write(to: file)
    let client = try S3Client(configuration: makeConfiguration(), transport: DelayedTransport())
    let task = Task {
        try await client.upload(fileURL: file, objectKey: "hello.txt", contentType: "text/plain")
    }
    await Task.yield()
    task.cancel()
    var wasCancelled = false
    do {
        try await task.value
        Issue.record("Expected the upload to be cancelled")
    } catch {
        wasCancelled = error is CancellationError
    }
    #expect(wasCancelled)
}

@Test("Transient network failures retry at most twice")
func transientUploadRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("hello.txt")
    try Data("hello".utf8).write(to: file)
    let transport = RetryingTransport()
    let client = try S3Client(configuration: makeConfiguration(), transport: transport)
    try await client.upload(fileURL: file, objectKey: "hello.txt", contentType: "text/plain")
    #expect(await transport.putAttempts == 2)
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    var maximum: Int64 { lock.withLock { values.max() ?? 0 } }
    func record(_ value: Int64) { lock.withLock { values.append(value) } }
}
