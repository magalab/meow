import os

enum MeowLog {
    static let app = Logger(subsystem: "tech.lury.meow", category: "app")
    static let ai = Logger(subsystem: "tech.lury.meow", category: "ai")
    static let authenticator = Logger(subsystem: "tech.lury.meow", category: "authenticator")
    static let capture = Logger(subsystem: "tech.lury.meow", category: "capture")
    static let calendar = Logger(subsystem: "tech.lury.meow", category: "calendar")
    static let clipboard = Logger(subsystem: "tech.lury.meow", category: "clipboard")
    static let hotkey = Logger(subsystem: "tech.lury.meow", category: "hotkey")
    static let localization = Logger(subsystem: "tech.lury.meow", category: "localization")
    static let recording = Logger(subsystem: "tech.lury.meow", category: "recording")
    static let settings = Logger(subsystem: "tech.lury.meow", category: "settings")
    static let speech = Logger(subsystem: "tech.lury.meow", category: "speech")
    static let system = Logger(subsystem: "tech.lury.meow", category: "system")
    static let translation = Logger(subsystem: "tech.lury.meow", category: "translation")
    static let upload = Logger(subsystem: "tech.lury.meow", category: "upload")
    static let whiteboard = Logger(subsystem: "tech.lury.meow", category: "whiteboard")
}
