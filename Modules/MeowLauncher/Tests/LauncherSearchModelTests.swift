import Foundation
import MeowClipboard
import MeowLauncher
import Testing

struct LauncherSearchModelTests {
    @Test
    func searchItemIdentityAndPrimaryTextRemainStable() {
        let app = AppEntry(
            id: "/Applications/Example.app",
            name: "Example",
            bundleId: "com.example.app",
            url: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let command = CommandEntry(
            id: "meow.quit",
            title: "Quit",
            subtitle: "Quit Meow",
            keywords: ["exit"]
        )
        let clipboardEntry = ClipboardEntry(
            id: "clipboard-1",
            content: .text("Copied text"),
            copiedAt: Date(timeIntervalSince1970: 0)
        )
        let calculation = CalculationEntry(expression: "1 + 1", result: "2")

        #expect(SearchItem.app(app).id == "app:/Applications/Example.app")
        #expect(SearchItem.app(app).primaryText == "Example")
        #expect(SearchItem.command(command).id == "command:meow.quit")
        #expect(SearchItem.command(command).primaryText == "Quit")
        #expect(SearchItem.clipboard(clipboardEntry).id == "clipboard:clipboard-1")
        #expect(SearchItem.clipboard(clipboardEntry).primaryText == "Copied text")
        #expect(SearchItem.calculation(calculation).id == "calculation:1 + 1")
        #expect(SearchItem.calculation(calculation).primaryText == "2")
    }
}
