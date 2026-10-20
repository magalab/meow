import AppKit
import SwiftUI

@main
struct MeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.menuPreferences) {
                    (NSApp.delegate as? AppDelegate)?.openPreferencesFromCommand()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let compositionRoot = AppCompositionRoot()

    func applicationDidFinishLaunching(_ notification: Notification) {
        compositionRoot.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        compositionRoot.applicationWillTerminate(notification)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        compositionRoot.applicationShouldTerminate(sender)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        compositionRoot.applicationDidBecomeActive(notification)
    }

    func openPreferencesFromCommand() {
        compositionRoot.openPreferencesFromCommand()
    }
}
