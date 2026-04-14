import AppKit
import SwiftUI

struct SearchItemIcon: View {
    let item: SearchItem
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        Group {
            switch item {
            case .app(let app):
                LazyAppIconView(path: app.url.path)
            case .command:
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.launcherAccent)
            case .clipboard(let entry):
                if case .image(let imageContent) = entry.content {
                    LazyClipboardImageView(path: imageContent.thumbnailPath)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.launcherAccent)
                }
            }
        }
        .frame(width: 32, height: 32)
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
            nsImage = NSWorkspace.shared.icon(forFile: path)
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
            nsImage = NSImage(contentsOfFile: path)
        }
        .onDisappear {
            nsImage = nil
        }
    }
}

struct ClipboardContextMenu: ViewModifier {
    let item: SearchItem
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if case .clipboard = item {
            content.contextMenu {
                Button(L10n.clipboardDelete) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}
