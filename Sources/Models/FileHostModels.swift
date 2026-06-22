import Foundation

enum S3PublicURLStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case customDomain
    case publicBucket
    case presigned

    var id: String { rawValue }
}

enum S3URLStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case path
    case virtualHosted

    var id: String { rawValue }
}

enum LinkFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case url
    case markdown
    case html

    var id: String { rawValue }

    func format(url: URL, filename: String, mimeType: String) -> String {
        let value = url.absoluteString
        let isImage = mimeType.hasPrefix("image/")
        switch self {
        case .url:
            return value
        case .markdown:
            let escapedName = filename.replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            return isImage ? "![](\(value))" : "[\(escapedName)](\(value))"
        case .html:
            let escapedURL = Self.escapeHTML(value)
            let escapedName = Self.escapeHTML(filename)
            return isImage
                ? "<img src=\"\(escapedURL)\" alt=\"\(escapedName)\">"
                : "<a href=\"\(escapedURL)\">\(escapedName)</a>"
        }
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct S3Config: Codable, Equatable, Sendable {
    var id = UUID()
    var name = "S3"
    var endpoint = ""
    var region = "us-east-1"
    var accessKeyID = ""
    var bucket = ""
    var objectKeyTemplate = "{year}/{month}/{day}/{filename}-{random}.{ext}"
    var publicURLStrategy = S3PublicURLStrategy.customDomain
    var publicBaseURL = ""
    var presignedURLExpiration = 3600
    var urlStyle = S3URLStyle.virtualHosted
    var isEnabled = false

    private enum CodingKeys: String, CodingKey {
        case id, name, endpoint, region, accessKeyID, bucket, objectKeyTemplate
        case publicURLStrategy, publicBaseURL, presignedURLExpiration, urlStyle, isEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "S3"
        endpoint = try values.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        region = try values.decodeIfPresent(String.self, forKey: .region) ?? "us-east-1"
        accessKeyID = try values.decodeIfPresent(String.self, forKey: .accessKeyID) ?? ""
        bucket = try values.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        objectKeyTemplate = try values.decodeIfPresent(String.self, forKey: .objectKeyTemplate)
            ?? "{year}/{month}/{day}/{filename}-{random}.{ext}"
        publicURLStrategy = try values.decodeIfPresent(S3PublicURLStrategy.self, forKey: .publicURLStrategy) ?? .customDomain
        publicBaseURL = try values.decodeIfPresent(String.self, forKey: .publicBaseURL) ?? ""
        presignedURLExpiration = try values.decodeIfPresent(Int.self, forKey: .presignedURLExpiration) ?? 3600
        urlStyle = try values.decodeIfPresent(S3URLStyle.self, forKey: .urlStyle) ?? .virtualHosted
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

struct FileHostSettings: Codable, Equatable, Sendable {
    var s3Configurations: [S3Config]
    var selectedS3ConfigID: UUID
    var linkFormat = LinkFormat.markdown
    var historyLimit = 50
    var maximumFileSizeMB = 5120
    var uploadHotkeyKeyCode: UInt32 = 0
    var uploadHotkeyModifiers: UInt32 = 0

    var s3: S3Config {
        get {
            s3Configurations.first(where: { $0.id == selectedS3ConfigID })
                ?? s3Configurations.first
                ?? S3Config()
        }
        set {
            if let index = s3Configurations.firstIndex(where: { $0.id == newValue.id }) {
                s3Configurations[index] = newValue
            } else {
                s3Configurations.append(newValue)
            }
            selectedS3ConfigID = newValue.id
        }
    }

    static let `default` = FileHostSettings()

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case s3, s3Configurations, selectedS3ConfigID, linkFormat, historyLimit, maximumFileSizeMB
        case uploadHotkeyKeyCode, uploadHotkeyModifiers
    }

    init() {
        let config = S3Config()
        s3Configurations = [config]
        selectedS3ConfigID = config.id
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyConfig = try values.decodeIfPresent(S3Config.self, forKey: .s3)
        var decodedConfigurations = try values.decodeIfPresent([S3Config].self, forKey: .s3Configurations) ?? []
        if decodedConfigurations.isEmpty {
            decodedConfigurations = [legacyConfig ?? S3Config()]
        }
        s3Configurations = decodedConfigurations
        if let decodedSelection = try values.decodeIfPresent(UUID.self, forKey: .selectedS3ConfigID),
           decodedConfigurations.contains(where: { $0.id == decodedSelection })
        {
            selectedS3ConfigID = decodedSelection
        } else {
            selectedS3ConfigID = decodedConfigurations[0].id
        }
        linkFormat = try values.decodeIfPresent(LinkFormat.self, forKey: .linkFormat) ?? Self.default.linkFormat
        historyLimit = try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? Self.default.historyLimit
        maximumFileSizeMB = try values.decodeIfPresent(Int.self, forKey: .maximumFileSizeMB) ?? Self.default.maximumFileSizeMB
        uploadHotkeyKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .uploadHotkeyKeyCode) ?? 0
        uploadHotkeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .uploadHotkeyModifiers) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(s3Configurations, forKey: .s3Configurations)
        try values.encode(selectedS3ConfigID, forKey: .selectedS3ConfigID)
        try values.encode(linkFormat, forKey: .linkFormat)
        try values.encode(historyLimit, forKey: .historyLimit)
        try values.encode(maximumFileSizeMB, forKey: .maximumFileSizeMB)
        try values.encode(uploadHotkeyKeyCode, forKey: .uploadHotkeyKeyCode)
        try values.encode(uploadHotkeyModifiers, forKey: .uploadHotkeyModifiers)
    }

    func s3Configuration(id: UUID) -> S3Config? {
        s3Configurations.first(where: { $0.id == id })
    }
}

struct UploadHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let fileSize: Int64
    let mimeType: String
    let uploadedURL: String?
    let objectKey: String
    let backendKind: String
    let backendConfigID: UUID
    let backendName: String?
    let thumbnailPath: String?
    let createdAt: Date

    init(
        id: UUID,
        filename: String,
        fileSize: Int64,
        mimeType: String,
        uploadedURL: String?,
        objectKey: String,
        backendKind: String,
        backendConfigID: UUID,
        backendName: String? = nil,
        thumbnailPath: String?,
        createdAt: Date
    ) {
        self.id = id
        self.filename = filename
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.uploadedURL = uploadedURL
        self.objectKey = objectKey
        self.backendKind = backendKind
        self.backendConfigID = backendConfigID
        self.backendName = backendName
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
    }
}

enum UploadError: LocalizedError, Sendable, Equatable {
    case notConfigured
    case fileTooLarge(Int64)
    case s3Error(String)
    case networkError(String)
    case invalidResponse
    case clipboardContentUnavailable
    case fileUnreadable(String)
    case secretRequired
    case credentialUnavailable
    case shareURLNotConfigured
    case publicURLUnavailable
    case shareURLVerificationFailed(Int, String)
    case shareURLInvalidResponse(String)
    case invalidR2Endpoint
    case alreadyUploading
    case invalidObjectKey
    case remoteDeletionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L10n.uploadErrorNotConfigured
        case let .fileTooLarge(bytes): return String(format: L10n.uploadErrorFileTooLarge, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        case let .s3Error(message), let .networkError(message): return message
        case .invalidResponse: return L10n.uploadErrorInvalidResponse
        case .clipboardContentUnavailable: return L10n.uploadErrorClipboardContentUnavailable
        case let .fileUnreadable(filename):
            return String(format: L10n.uploadErrorFileUnreadable, filename)
        case .secretRequired: return L10n.uploadErrorSecretRequired
        case .credentialUnavailable: return L10n.uploadErrorCredentialUnavailable
        case .shareURLNotConfigured: return L10n.uploadErrorShareURLNotConfigured
        case .publicURLUnavailable: return L10n.uploadErrorPublicURLUnavailable
        case let .shareURLVerificationFailed(statusCode, url):
            return String(format: L10n.uploadErrorShareURLVerificationFailed, statusCode, url)
        case let .shareURLInvalidResponse(url):
            return String(format: L10n.uploadErrorShareURLInvalidResponse, url)
        case .invalidR2Endpoint: return L10n.uploadErrorInvalidR2Endpoint
        case .alreadyUploading: return L10n.uploadErrorAlreadyUploading
        case .invalidObjectKey: return L10n.uploadErrorInvalidObjectKey
        case let .remoteDeletionFailed(filenames):
            return String(format: L10n.uploadErrorRemoteDeletionFailed, filenames)
        case .cancelled: return L10n.uploadErrorCancelled
        }
    }
}

enum ObjectKeyBuilder {
    static func build(template: String, fileURL: URL, date: Date = Date(), random: String? = nil) throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let fields = [("year", "yyyy"), ("month", "MM"), ("day", "dd"), ("hour", "HH"), ("minute", "mm"), ("second", "ss")]
        var value = template
        for (name, format) in fields {
            formatter.dateFormat = format
            value = value.replacingOccurrences(of: "{\(name)}", with: formatter.string(from: date))
        }
        let ext = fileURL.pathExtension
        let filename = fileURL.deletingPathExtension().lastPathComponent
        value = value.replacingOccurrences(of: "{filename}", with: filename)
            .replacingOccurrences(of: "{ext}", with: ext)
            .replacingOccurrences(of: "{random}", with: random ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased())
            .replacingOccurrences(of: "{uuid}", with: UUID().uuidString.lowercased())

        let controls = CharacterSet.controlCharacters
        let segments = value.components(separatedBy: "/").compactMap { segment -> String? in
            let clean = segment.components(separatedBy: controls).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean != ".", clean != ".." else { return nil }
            return clean
        }
        guard !segments.isEmpty else { throw UploadError.invalidObjectKey }
        return segments.joined(separator: "/")
    }

    static func encodedPath(_ objectKey: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return objectKey.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
    }
}
