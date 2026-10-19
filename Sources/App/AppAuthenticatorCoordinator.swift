import AppKit

@MainActor
final class AppAuthenticatorCoordinator {
    struct Actions {
        let authenticatorEnabled: @MainActor () -> Bool
        let enableAuthenticator: @MainActor () -> Void
        let importOTPAuth: @MainActor (String) throws -> Void
        let showAuthenticator: @MainActor () -> Void
        let presentInvalidOTPAuth: @MainActor () -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func handleOTPAuthImport(_ payload: String) {
        guard let parsed = OTPAuthURL.parse(payload) else {
            actions.presentInvalidOTPAuth()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.screenshotQRImportOTPTitle
        alert.informativeText = String(
            format: L10n.screenshotQRImportOTPMessage,
            parsed.issuer.isEmpty ? "-" : parsed.issuer,
            parsed.account
        )
        alert.addButton(withTitle: L10n.screenshotQRImportOTPConfirm)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if !actions.authenticatorEnabled() {
                actions.enableAuthenticator()
            }
            try actions.importOTPAuth(payload)
            actions.showAuthenticator()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = L10n.screenshotQRImportOTPFailed
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: L10n.actionOK)
            failure.runModal()
        }
    }

    func presentQRCodeResult(_ payload: String) {
        let url = URL(string: payload)
        let canOpen = url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false

        let alert = NSAlert()
        alert.messageText = L10n.screenshotQRResultTitle
        alert.informativeText = payload
        if canOpen {
            alert.addButton(withTitle: L10n.screenshotQROpen)
        }
        alert.addButton(withTitle: L10n.actionMenuCopy)
        alert.addButton(withTitle: L10n.actionCancel)
        let response = alert.runModal()

        if canOpen, response == .alertFirstButtonReturn, let url {
            NSWorkspace.shared.open(url)
            return
        }

        let copyResponse = canOpen ? NSApplication.ModalResponse.alertSecondButtonReturn : .alertFirstButtonReturn
        if response == copyResponse {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
        }
    }
}
