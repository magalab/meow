public struct CaptureExportOptions: Equatable, Sendable {
    public let saveDirectory: String
    public let fileNameTemplate: String
    public let imageFormat: ScreenshotImageFormat
    public let jpegQuality: Double

    public init(
        saveDirectory: String,
        fileNameTemplate: String,
        imageFormat: ScreenshotImageFormat,
        jpegQuality: Double
    ) {
        self.saveDirectory = saveDirectory
        self.fileNameTemplate = fileNameTemplate
        self.imageFormat = imageFormat
        self.jpegQuality = jpegQuality
    }
}
