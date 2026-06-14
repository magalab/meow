import AppKit
import SwiftUI

struct RecordingPreviewView: View {
    let artifact: RecordingArtifact
    let onTrim: () -> Void
    let onClose: () -> Void

    init(
        artifact: RecordingArtifact,
        onTrim: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.artifact = artifact
        self.onTrim = onTrim
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 12) {
            if artifact.width > 0 {
                previewImage
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 42))
                    Text(artifact.fileURL.lastPathComponent)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            HStack {
                Text(artifact.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(L10n.recordingPreviewFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact.fileURL])
                }
                Button(L10n.recordingPreviewOpen) {
                    NSWorkspace.shared.open(artifact.fileURL)
                }
                if artifact.width > 0 {
                    Button(L10n.recordingPreviewTrim, action: onTrim)
                }
                Button(L10n.actionOK, action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(minWidth: 520)
    }

    private var previewHeight: CGFloat {
        let width = max(1, artifact.width)
        let height = max(1, artifact.height)
        let aspectRatio = CGFloat(height) / CGFloat(width)
        return min(420, max(220, 520 * aspectRatio))
    }

    @ViewBuilder
    private var previewImage: some View {
        if let thumbnailURL = artifact.thumbnailURL,
           let image = NSImage(contentsOf: thumbnailURL)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 42))
                Text(artifact.fileURL.lastPathComponent)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }
}
