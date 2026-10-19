import AppKit
import MeowCapture
import Testing

struct CaptureEditorModelTests {
    @Test("Capture editor command stack supports undo and redo")
    @MainActor
    func undoRedo() {
        let model = CaptureEditorModel(sourceSize: CGSize(width: 100, height: 80))
        let command = CaptureEditorCommand.rectangle(
            rect: CGRect(x: 10, y: 10, width: 30, height: 20),
            color: .red,
            width: 4
        )

        model.add(command)
        #expect(model.commands == [command])
        #expect(model.canUndo)

        model.undo()
        #expect(model.commands.isEmpty)
        #expect(model.canRedo)

        model.redo()
        #expect(model.commands == [command])
        #expect(model.canUndo)
        #expect(!model.canRedo)
    }

    @Test("Capture editor crop bounds update output dimensions")
    @MainActor
    func cropBoundsAndReset() {
        let model = CaptureEditorModel(sourceSize: CGSize(width: 100, height: 80))

        model.setCropRect(CGRect(x: -5, y: 10, width: 50, height: 40))
        #expect(model.cropRect == CGRect(x: 0, y: 10, width: 45, height: 40))
        #expect(model.outputWidth == 45)
        #expect(model.outputHeight == 40)

        model.setCropRect(nil)
        #expect(model.cropRect == nil)
        #expect(model.outputWidth == 100)
        #expect(model.outputHeight == 80)
    }

    @Test("Capture editor resizing preserves aspect ratio and clamps dimensions")
    @MainActor
    func resizePreservesAspectRatioAndClamps() {
        let model = CaptureEditorModel(sourceSize: CGSize(width: 100, height: 50))

        model.setOutputWidth(200)
        #expect(model.outputWidth == 200)
        #expect(model.outputHeight == 100)

        model.setOutputHeight(20_000)
        #expect(model.outputHeight == 16_384)
        #expect(model.outputWidth == 32_768)

        model.setOutputWidth(-1)
        #expect(model.outputWidth == 1)
        #expect(model.outputHeight == 1)
    }
}
