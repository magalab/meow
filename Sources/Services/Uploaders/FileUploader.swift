import Foundation

struct UploadRequest: Sendable {
    let fileURL: URL
    let objectKey: String
    let fileSize: Int64
    let mimeType: String
}

struct UploadProgress: Sendable, Equatable {
    let sentBytes: Int64
    let totalBytes: Int64
}

struct UploadResult: Sendable, Equatable {
    let objectKey: String
    let shareURL: URL
    let fileSize: Int64
    let mimeType: String
}

protocol FileUploader: Sendable {
    func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> UploadResult

    func shareURL(for objectKey: String) async throws -> URL
    func deleteObject(for objectKey: String) async throws
    func shutdown() async throws
}

extension FileUploader {
    func deleteObject(for _: String) async throws { throw UploadError.notConfigured }
    func shutdown() async throws {}
}

protocol UploaderCreating: Sendable {
    func makeUploader(config: S3Config, secretAccessKey: String) throws -> any FileUploader
}

struct UploaderFactory: UploaderCreating {
    func makeUploader(config: S3Config, secretAccessKey: String) throws -> any FileUploader {
        try S3Uploader(config: config, secretAccessKey: secretAccessKey)
    }
}
