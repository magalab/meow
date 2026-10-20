import AppKit

public extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    func resized(toFit boundingSize: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(boundingSize.width / size.width, boundingSize.height / size.height, 1)
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    func resized(to boundingSize: NSSize) -> NSImage {
        resized(toFit: boundingSize)
    }
}
