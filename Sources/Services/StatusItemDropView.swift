import AppKit

final class StatusItemDropView: NSView {
    var isDropEnabled: Bool
    private let onDrop: (URL) -> Void

    init(isEnabled: Bool, onDrop: @escaping (URL) -> Void) {
        isDropEnabled = isEnabled
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isDropEnabled, hasFileURL(sender) else { return [] }
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.backgroundColor = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropEnabled && hasFileURL(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.backgroundColor = nil
        guard isDropEnabled,
              let urls = sender.draggingPasteboard.readObjects(
                  forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]
              ) as? [URL],
              let url = urls.first
        else { return false }
        onDrop(url)
        return true
    }

    private func hasFileURL(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}
