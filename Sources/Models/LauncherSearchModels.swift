import MeowClipboard
import Foundation
import MeowLauncher

struct CalculationEntry: Identifiable, Hashable {
    let expression: String
    let result: String

    var id: String { "calculation:\(expression)" }
}

enum SearchItem: Identifiable, Hashable {
    case app(AppEntry)
    case command(CommandEntry)
    case clipboard(ClipboardEntry)
    case calculation(CalculationEntry)

    var id: String {
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

    var primaryText: String {
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

    var secondaryText: String {
        switch self {
        case .app:
            return L10n.categoryApplication
        case let .command(command):
            return command.subtitle
        case let .clipboard(entry):
            return entry.content.localizedTypeLabel
        case .calculation:
            return L10n.calculatorResult
        }
    }

    var symbolName: String {
        switch self {
        case .app:
            return "app.fill"
        case let .command(command):
            if command.id == "meow.preferences" { return "slider.horizontal.3" }
            if command.id == "meow.quit" { return "power" }
            if command.id == "meow.authenticator" { return AuthenticatorVisuals.symbol }
            if command.id.hasPrefix("meow.screenshot.") { return "camera.viewfinder" }
            return "command"
        case let .clipboard(entry):
            return entry.symbolName
        case .calculation:
            return "equal.circle.fill"
        }
    }
}

extension ClipboardContent {
    var localizedTypeLabel: String {
        switch self {
        case .text: L10n.clipboardTypeText
        case .image: L10n.clipboardTypeImage
        case .file: L10n.clipboardTypeFile
        case .url: L10n.clipboardTypeURL
        case .audio: L10n.clipboardTypeAudio
        }
    }
}
