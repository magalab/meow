import MeowClipboard

public struct CalculationEntry: Identifiable, Hashable, Sendable {
    public let expression: String
    public let result: String

    public init(expression: String, result: String) {
        self.expression = expression
        self.result = result
    }

    public var id: String { "calculation:\(expression)" }
}

public enum SearchItem: Identifiable, Hashable {
    case app(AppEntry)
    case command(CommandEntry)
    case clipboard(ClipboardEntry)
    case calculation(CalculationEntry)

    public var id: String {
        switch self {
        case let .app(app):
            return "app:\(app.id)"
        case let .command(command):
            return "command:\(command.id)"
        case let .clipboard(entry):
            return "clipboard:\(entry.id)"
        case let .calculation(calculation):
            return calculation.id
        }
    }

    public var primaryText: String {
        switch self {
        case let .app(app):
            return app.name
        case let .command(command):
            return command.title
        case let .clipboard(entry):
            return entry.preview
        case let .calculation(calculation):
            return calculation.result
        }
    }
}
