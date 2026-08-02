import Foundation
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard configuration")
struct WhiteboardConfigurationTests {
    @Test("Edit opacity is normalized")
    func editOpacityIsNormalized() {
        let directory = URL(fileURLWithPath: "/tmp/meow-whiteboard-tests")

        let low = WhiteboardConfiguration(
            isEnabled: false,
            editOpacity: -2,
            storageDirectory: directory
        )
        let high = WhiteboardConfiguration(
            isEnabled: false,
            editOpacity: 5,
            storageDirectory: directory
        )
        let notANumber = WhiteboardConfiguration(
            isEnabled: false,
            editOpacity: .nan,
            storageDirectory: directory
        )

        #expect(low.editOpacity == 0.2)
        #expect(high.editOpacity == 1)
        #expect(notANumber.editOpacity == 0.94)
    }

    @Test("Recommended defaults remain opt-in")
    func recommendedDefaultsRemainOptIn() {
        let configuration = WhiteboardConfiguration(
            isEnabled: false,
            storageDirectory: URL(fileURLWithPath: "/tmp/meow-whiteboard-tests")
        )

        #expect(!configuration.isEnabled)
        #expect(configuration.idleVisibility == .hidden)
        #expect(configuration.includeInCaptures)
        #expect(configuration.surfaceStyle == .paper)
        #expect(configuration.guideStyle == .dots)
        #expect(configuration.outputBackgroundStyle == .transparent)
    }

    @Test("Disabled controller does not create or read workspace storage")
    @MainActor
    func disabledControllerHasNoRuntimeFootprint() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-WhiteboardDisabledTests-\(UUID().uuidString)")
        let controller = WhiteboardFeatureController()

        controller.start(configuration: WhiteboardConfiguration(
            isEnabled: false,
            storageDirectory: directory
        ))

        #expect(controller.state == .disabled)
        #expect(controller.captureWindowNumber == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Whiteboard localization keys exist in English and Simplified Chinese")
    func localizationResourcesAreComplete() throws {
        let moduleRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceRoot = moduleRoot.appendingPathComponent("Sources/Resources", isDirectory: true)
        let keys = [
            "whiteboard.window.title",
            "whiteboard.toolbar.title",
            "whiteboard.tool.select",
            "whiteboard.tool.rectangle",
            "whiteboard.tool.ellipse",
            "whiteboard.tool.diamond",
            "whiteboard.tool.arrow",
            "whiteboard.tool.line",
            "whiteboard.tool.pen",
            "whiteboard.tool.text",
            "whiteboard.tool.eraser",
            "whiteboard.action.undo",
            "whiteboard.action.redo",
            "whiteboard.action.fit",
            "whiteboard.action.import",
            "whiteboard.action.export",
            "whiteboard.action.done",
            "whiteboard.action.add",
            "whiteboard.action.cancel",
            "whiteboard.action.save",
            "whiteboard.style.title",
            "whiteboard.style.stroke",
            "whiteboard.style.fill",
            "whiteboard.style.lineWidth",
            "whiteboard.style.opacity",
            "whiteboard.text.add",
            "whiteboard.text.edit",
            "whiteboard.text.placeholder",
            "whiteboard.import.title",
            "whiteboard.import.confirm.title",
            "whiteboard.import.confirm.message",
            "whiteboard.export.title",
            "whiteboard.empty.title",
            "whiteboard.empty.subtitle",
            "whiteboard.empty.shortcuts",
            "whiteboard.error.image.too.large",
            "whiteboard.error.document.too.large",
            "whiteboard.error.export.context",
            "whiteboard.error.export.encoding",
            "whiteboard.error.export.too.large",
            "whiteboard.error.schema.unsupported",
            "whiteboard.error.excalidraw.root",
            "whiteboard.error.excalidraw.elements",
            "whiteboard.error.excalidraw.duplicate.id",
            "whiteboard.error.excalidraw.images.too.large",
            "whiteboard.error.workspace.recovered",
            "whiteboard.error.workspace.recovery.failed",
        ]

        for language in ["en", "zh-Hans"] {
            let url = resourceRoot
                .appendingPathComponent("\(language).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings")
            let contents = try String(contentsOf: url, encoding: .utf8)
            for key in keys {
                #expect(contents.contains("\"\(key)\" ="))
            }
        }
    }
}
