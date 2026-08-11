import AppKit
import SwiftUI

@MainActor
private enum SearchItemImageCache {
    static let appIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        return cache
    }()

    static let clipboardImages: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()
}

struct SearchItemIcon: View {
    let item: SearchItem
    let theme: AppTheme
    let showClipboardImagePreviews: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        Group {
            switch item {
            case let .app(app):
                LazyAppIconView(path: app.url.path)
            case .command:
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.launcherAccent)
            case let .clipboard(entry):
                if showClipboardImagePreviews,
                   case let .image(imageContent) = entry.content {
                    LazyClipboardImageView(path: imageContent.thumbnailPath)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.launcherAccent)
                }
            }
        }
        .frame(width: 28, height: 28)
        .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct LazyAppIconView: View {
    let path: String
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .onAppear {
            guard nsImage == nil else { return }
            let cacheKey = path as NSString
            if let cachedImage = SearchItemImageCache.appIcons.object(forKey: cacheKey) {
                nsImage = cachedImage
                return
            }

            let image = NSWorkspace.shared.icon(forFile: path)
            SearchItemImageCache.appIcons.setObject(image, forKey: cacheKey)
            nsImage = image
        }
        .onDisappear {
            nsImage = nil
        }
    }
}

private struct LazyClipboardImageView: View {
    let path: String
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .onAppear {
            guard nsImage == nil else { return }
            let cacheKey = path as NSString
            if let cachedImage = SearchItemImageCache.clipboardImages.object(forKey: cacheKey) {
                nsImage = cachedImage
                return
            }

            guard let image = NSImage(contentsOfFile: path) else { return }
            SearchItemImageCache.clipboardImages.setObject(image, forKey: cacheKey)
            nsImage = image
        }
        .onDisappear {
            nsImage = nil
        }
    }
}

struct ClipboardContextMenu: ViewModifier {
    let item: SearchItem
    let onTogglePinned: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if case .clipboard = item {
            content.contextMenu {
                Button {
                    onTogglePinned()
                } label: {
                    if case let .clipboard(entry) = item {
                        Label(
                            entry.isPinned ? L10n.clipboardUnpin : L10n.clipboardPin,
                            systemImage: entry.isPinned ? "pin.slash" : "pin"
                        )
                    }
                }
                Button(L10n.clipboardDelete) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}
