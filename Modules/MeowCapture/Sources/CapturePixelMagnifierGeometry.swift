import CoreGraphics

public enum CapturePixelMagnifierGeometry {
    public static func sampleRect(
        at point: CGPoint,
        in bounds: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        scale: CGFloat
    ) -> CGRect {
        let pixelX = min(max(0, Int((point.x * scale).rounded(.down))), imageWidth - 1)
        let pixelY = min(max(0, Int(((bounds.height - point.y) * scale).rounded(.down))), imageHeight - 1)
        let width = min(13, imageWidth)
        let height = min(13, imageHeight)
        return CGRect(
            x: min(max(0, pixelX - width / 2), imageWidth - width),
            y: min(max(0, pixelY - height / 2), imageHeight - height),
            width: width,
            height: height
        )
    }

    public static func frame(near point: CGPoint, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 140, height: 140)
        let margin: CGFloat = 22
        let x = point.x + margin + size.width <= bounds.maxX
            ? point.x + margin : point.x - margin - size.width
        let y = point.y - margin - size.height >= bounds.minY
            ? point.y - margin - size.height : point.y + margin
        return CGRect(
            x: min(max(bounds.minX, x), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(bounds.minY, y), max(bounds.minY, bounds.maxY - size.height)),
            width: size.width,
            height: size.height
        )
    }
}
