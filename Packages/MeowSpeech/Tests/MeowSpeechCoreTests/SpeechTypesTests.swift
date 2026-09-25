import Foundation
import MeowSpeechCore
import Testing

@Test("Speech model manifests expose stable artifact paths")
func speechModelManifestPaths() {
    let manifest = SpeechModelManifest(
        id: "demo",
        version: "1",
        backend: "test",
        artifacts: [
            SpeechModelArtifact(
                id: "one",
                relativePath: "model.bin",
                remoteURL: URL(string: "https://example.com/model.bin")!,
                sha256: "abc"
            ),
        ]
    )

    #expect(manifest.id == "demo")
    #expect(manifest.requiredRelativePaths == ["model.bin"])
}

@Test("Speech errors keep user-facing context")
func speechErrorsDescribeContext() {
    #expect(SpeechError.modelUnavailable.errorDescription?.isEmpty == false)
    #expect(SpeechError.inferenceFailed("bad logits").errorDescription == "bad logits")
}
