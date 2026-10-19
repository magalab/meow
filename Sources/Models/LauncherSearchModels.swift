import MeowClipboard
import MeowLauncher

extension SearchItem {
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
