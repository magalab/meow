import Foundation
import Testing
@testable import WhiteboardFeature

@Suite("Whiteboard performance")
struct WhiteboardPerformanceTests {
    @Test("Large element collections meet the serialization smoke baseline")
    func elementCollectionSerializationBaseline() throws {
        for count in [100, 1_000, 5_000] {
            let directory = temporaryDirectory(label: "elements-\(count)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = WhiteboardDocumentStore(directory: directory)
            var document = WhiteboardDocument.empty()
            document.elements = makeElements(count: count)

            let saveStarted = Date()
            try store.save(document)
            let saveDuration = Date().timeIntervalSince(saveStarted)
            let loadStarted = Date()
            let loaded = try store.load()
            let loadDuration = Date().timeIntervalSince(loadStarted)

            print(String(
                format: "[Whiteboard benchmark] %d elements: save %.3fs, load %.3fs",
                count,
                saveDuration,
                loadDuration
            ))
            #expect(loaded.elements.count == count)
            #expect(saveDuration < 10)
            #expect(loadDuration < 10)
        }
    }

    @Test("Extended document-size save baselines run on demand")
    func extendedDocumentSizeBaseline() throws {
        let requestedSizes = ProcessInfo.processInfo.environment["MEOW_WHITEBOARD_BENCHMARK_MB"]?
            .split(separator: ",")
            .compactMap { Int($0) } ?? []
        guard !requestedSizes.isEmpty else { return }

        for megabytes in requestedSizes where [10, 100].contains(megabytes) {
            let directory = temporaryDirectory(label: "payload-\(megabytes)mb")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = WhiteboardDocumentStore(directory: directory)
            var document = WhiteboardDocument.empty()
            document.elements = [WhiteboardElement(
                kind: .text,
                origin: WhiteboardPoint(x: 0, y: 0),
                size: WhiteboardSize(width: 600, height: 400),
                text: String(repeating: "x", count: megabytes * 1_024 * 1_024)
            )]

            let saveStarted = Date()
            try store.save(document)
            let saveDuration = Date().timeIntervalSince(saveStarted)
            let loadStarted = Date()
            let loaded = try store.load()
            let loadDuration = Date().timeIntervalSince(loadStarted)

            print(String(
                format: "[Whiteboard benchmark] %d MB payload: save %.3fs, load %.3fs",
                megabytes,
                saveDuration,
                loadDuration
            ))
            #expect(loaded.elements.first?.text?.count == megabytes * 1_024 * 1_024)
            #expect(saveDuration < 60)
            #expect(loadDuration < 60)
        }
    }

    private func makeElements(count: Int) -> [WhiteboardElement] {
        (0..<count).map { index in
            WhiteboardElement(
                kind: index.isMultiple(of: 3) ? .ellipse : .rectangle,
                origin: WhiteboardPoint(
                    x: Double(index % 50) * 24,
                    y: Double(index / 50) * 24
                ),
                size: WhiteboardSize(width: 20, height: 16),
                text: index.isMultiple(of: 7) ? "Element \(index)" : nil
            )
        }
    }

    private func temporaryDirectory(label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "Meow-WhiteboardBenchmark-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
