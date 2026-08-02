import AppKit
import SwiftUI

private enum WhiteboardToolbarLayout {
    static let initialWidth: CGFloat = 920
    static let expandedBreakpoint: CGFloat = 860
    static let stackedBreakpoint: CGFloat = 560
    static let singleRowHeight: CGFloat = 58
    static let stackedHeight: CGFloat = 92
}

@MainActor
final class WhiteboardToolbarPanel: NSPanel {
    init(
        session: WhiteboardSession,
        applicationName: String,
        onImport: @escaping () -> Void,
        onExport: @escaping (WhiteboardExportFormat) -> Void,
        onFit: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        let rootView = WhiteboardToolbarView(
            session: session,
            onImport: onImport,
            onExport: onExport,
            onFit: onFit,
            onFinish: onFinish
        )
        let hosting = NSHostingController(rootView: rootView)
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WhiteboardToolbarLayout.initialWidth,
                height: WhiteboardToolbarLayout.singleRowHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentViewController = hosting
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        title = WhiteboardLocalization.format("whiteboard.toolbar.title", applicationName)
    }

    func position(on screen: NSScreen) {
        var size = frame.size
        size.width = min(
            WhiteboardToolbarLayout.initialWidth,
            max(320, screen.visibleFrame.width - 24)
        )
        size.height = size.width < WhiteboardToolbarLayout.stackedBreakpoint
            ? WhiteboardToolbarLayout.stackedHeight
            : WhiteboardToolbarLayout.singleRowHeight
        setContentSize(size)
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 18
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct WhiteboardToolbarView: View {
    @ObservedObject var session: WhiteboardSession
    let onImport: () -> Void
    let onExport: (WhiteboardExportFormat) -> Void
    let onFit: () -> Void
    let onFinish: () -> Void
    @State private var showsStylePopover = false

    private let tools: [(WhiteboardTool, String)] = [
        (.select, "cursorarrow"),
        (.rectangle, "rectangle"),
        (.ellipse, "circle"),
        (.diamond, "diamond"),
        (.arrow, "arrow.up.right"),
        (.line, "line.diagonal"),
        (.pen, "pencil.tip"),
        (.text, "textformat"),
        (.eraser, "eraser"),
    ]

    var body: some View {
        GeometryReader { proxy in
            toolbarContent(for: proxy.size.width)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(2)
    }

    @ViewBuilder
    private func toolbarContent(for width: CGFloat) -> some View {
        if width >= WhiteboardToolbarLayout.expandedBreakpoint {
            expandedToolbar
        } else if width >= WhiteboardToolbarLayout.stackedBreakpoint - 4 {
            compactToolbar
        } else {
            stackedToolbar
        }
    }

    private var expandedToolbar: some View {
        HStack(spacing: 5) {
            toolButtons
            toolbarDivider
            historyButtons
            documentButtons
            toolbarDivider
            inlineStyleControls
            toolbarDivider
            doneButton(iconOnly: false)
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 5) {
            toolButtons
            toolbarDivider
            historyButtons
            documentButtons
            stylePopoverButton
            toolbarDivider
            doneButton(iconOnly: true)
        }
    }

    private var stackedToolbar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                toolButtons
            }
            HStack(spacing: 6) {
                historyButtons
                documentButtons
                toolbarDivider
                stylePopoverButton
                Spacer(minLength: 4)
                doneButton(iconOnly: true)
            }
        }
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 24)
    }

    private var toolButtons: some View {
        ForEach(tools, id: \.0) { tool, symbol in
            Button {
                session.selectedTool = tool
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        session.selectedTool == tool
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(WhiteboardLocalization.toolTitle(tool))
            .accessibilityLabel(WhiteboardLocalization.toolTitle(tool))
        }
    }

    private var historyButtons: some View {
        Group {
            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!session.canUndo)
            .help(WhiteboardLocalization.text("whiteboard.action.undo"))

            Button {
                session.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!session.canRedo)
            .help(WhiteboardLocalization.text("whiteboard.action.redo"))

            Button(action: onFit) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(WhiteboardLocalization.text("whiteboard.action.fit"))
        }
    }

    private var documentButtons: some View {
        Group {
            Button(action: onImport) {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(WhiteboardLocalization.text("whiteboard.action.import"))

            Menu {
                Button("PNG") { onExport(.png) }
                Button("SVG") { onExport(.svg) }
                Button("Excalidraw") { onExport(.excalidraw) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(WhiteboardLocalization.text("whiteboard.action.export"))
        }
    }

    private var inlineStyleControls: some View {
        Group {
            ColorPicker(
                WhiteboardLocalization.text("whiteboard.style.stroke"),
                selection: strokeColor,
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 28)
            .help(WhiteboardLocalization.text("whiteboard.style.stroke"))

            Toggle(isOn: fillEnabled) {
                Image(systemName: session.currentStyle.fillHex == nil ? "square" : "square.fill")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .help(WhiteboardLocalization.text("whiteboard.style.fill"))

            if session.currentStyle.fillHex != nil {
                ColorPicker(
                    WhiteboardLocalization.text("whiteboard.style.fill"),
                    selection: fillColor,
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 28)
            }

            Slider(value: lineWidth, in: 1...18, step: 1)
                .frame(width: 62)
                .help(WhiteboardLocalization.text("whiteboard.style.lineWidth"))

            Slider(value: opacity, in: 0.05...1, step: 0.05)
                .frame(width: 62)
                .help(WhiteboardLocalization.text("whiteboard.style.opacity"))
        }
    }

    private var stylePopoverButton: some View {
        Button {
            showsStylePopover.toggle()
        } label: {
            Image(systemName: "paintpalette")
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(WhiteboardLocalization.text("whiteboard.style.title"))
        .accessibilityLabel(WhiteboardLocalization.text("whiteboard.style.title"))
        .popover(isPresented: $showsStylePopover, arrowEdge: .bottom) {
            stylePopover
        }
    }

    private var stylePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(WhiteboardLocalization.text("whiteboard.style.stroke"))
                Spacer()
                ColorPicker(
                    WhiteboardLocalization.text("whiteboard.style.stroke"),
                    selection: strokeColor,
                    supportsOpacity: false
                )
                .labelsHidden()
            }

            HStack {
                Text(WhiteboardLocalization.text("whiteboard.style.fill"))
                Spacer()
                Toggle("", isOn: fillEnabled)
                    .labelsHidden()
                if session.currentStyle.fillHex != nil {
                    ColorPicker(
                        WhiteboardLocalization.text("whiteboard.style.fill"),
                        selection: fillColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(WhiteboardLocalization.text("whiteboard.style.lineWidth"))
                    Spacer()
                    Text("\(Int(session.currentStyle.lineWidth))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: lineWidth, in: 1...18, step: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(WhiteboardLocalization.text("whiteboard.style.opacity"))
                    Spacer()
                    Text("\(Int(session.currentStyle.opacity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: opacity, in: 0.05...1, step: 0.05)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(14)
        .frame(width: 260)
    }

    @ViewBuilder
    private func doneButton(iconOnly: Bool) -> some View {
        Button(action: onFinish) {
            if iconOnly {
                Image(systemName: "checkmark")
                    .frame(width: 26, height: 22)
            } else {
                Label(
                    WhiteboardLocalization.text("whiteboard.action.done"),
                    systemImage: "checkmark"
                )
                .lineLimit(1)
                .fixedSize()
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .layoutPriority(100)
        .help(WhiteboardLocalization.text("whiteboard.action.done"))
        .accessibilityLabel(WhiteboardLocalization.text("whiteboard.action.done"))
    }

    private var strokeColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(whiteboardHex: session.currentStyle.strokeHex)) },
            set: { color in
                var style = session.currentStyle
                style.strokeHex = NSColor(color).whiteboardHexString
                session.updateSelectedStyle(style)
            }
        )
    }

    private var fillEnabled: Binding<Bool> {
        Binding(
            get: { session.currentStyle.fillHex != nil },
            set: { enabled in
                var style = session.currentStyle
                style.fillHex = enabled ? (style.fillHex ?? "#DCEAFE") : nil
                session.updateSelectedStyle(style)
            }
        )
    }

    private var fillColor: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(whiteboardHex: session.currentStyle.fillHex ?? "#DCEAFE"))
            },
            set: { color in
                var style = session.currentStyle
                style.fillHex = NSColor(color).whiteboardHexString
                session.updateSelectedStyle(style)
            }
        )
    }

    private var lineWidth: Binding<Double> {
        Binding(
            get: { session.currentStyle.lineWidth },
            set: { value in
                var style = session.currentStyle
                style.lineWidth = value
                session.updateSelectedStyle(style)
            }
        )
    }

    private var opacity: Binding<Double> {
        Binding(
            get: { session.currentStyle.opacity },
            set: { value in
                var style = session.currentStyle
                style.opacity = value
                session.updateSelectedStyle(style)
            }
        )
    }
}
