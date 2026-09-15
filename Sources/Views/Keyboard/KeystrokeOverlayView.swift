import SwiftUI

@MainActor
final class KeystrokeOverlayViewModel: ObservableObject {
    @Published var items: [KeystrokeDisplayItem] = []
    @Published var theme: AppTheme = .gingerCat
    @Published var style: KeystrokeOverlayStyle = .compact
    @Published var opacity: Double = 0.82
    @Published var historyCount: KeystrokeHistoryCount = .one

    func apply(theme: AppTheme, style: KeystrokeOverlayStyle, opacity: Double, historyCount: KeystrokeHistoryCount) {
        self.theme = theme
        self.style = style
        self.opacity = min(max(opacity, 0.35), 1.0)
        self.historyCount = historyCount
        items = Array(items.suffix(historyCount.rawValue))
    }

    func show(label: String, isModifierOnly: Bool) {
        let existingItems = isModifierOnly ? items : items.filter { !$0.isModifierOnly }
        let updated = (existingItems + [KeystrokeDisplayItem(label: label, isModifierOnly: isModifierOnly)])
            .suffix(historyCount.rawValue)
        items = Array(updated)
    }

    func clear() {
        items = []
    }
}

struct KeystrokeOverlayView: View {
    @ObservedObject var viewModel: KeystrokeOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: viewModel.theme, scheme: colorScheme)
    }

    private var isProminent: Bool {
        viewModel.style == .prominent
    }

    private var overlaySize: CGSize {
        KeystrokeOverlayLayout.size(style: viewModel.style, historyCount: viewModel.historyCount)
    }

    var body: some View {
        HStack(spacing: isProminent ? 8 : 6) {
            Image(systemName: "keyboard")
                .font(.system(size: isProminent ? 17 : 13, weight: .semibold))
                .foregroundStyle(palette.launcherAccent)
                .frame(width: isProminent ? 31 : 24, height: isProminent ? 31 : 24)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: isProminent ? 7 : 4) {
                ForEach(viewModel.items) { item in
                    Text(item.label)
                        .font(.system(size: isProminent ? 18 : 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, isProminent ? 9 : 7)
                        .frame(height: isProminent ? 32 : 24)
                        .background(palette.selectionBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(palette.selectionStroke, lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isProminent ? 10 : 8)
        .padding(.vertical, isProminent ? 8 : 6)
        .frame(width: overlaySize.width, height: overlaySize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
        .opacity(viewModel.opacity)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 18, y: 8)
        .contentShape(Rectangle())
    }
}
