import AppKit
import SwiftUI

@MainActor
final class AppPreferencesCoordinator {
    struct Dependencies {
        let viewModel: LauncherViewModel
        let clipboardStore: ClipboardStore
        let navigation: PreferencesNavigationState
        let aiChatHistoryStore: AIChatHistoryStore
        let keystrokeVisualizerService: KeystrokeVisualizerService
        let authenticatorService: AuthenticatorService
        let healthReminderService: HealthReminderService
        let keepAwakeService: KeepAwakeService
        let fileUploadService: FileUploadService
        let recordingStore: RecordingStore
        let makeCaptureHistoryView: @MainActor (AppTheme) -> CaptureHistoryView
        let showRecordingTrimmer: @MainActor (URL) -> Void
        #if MEOW_VOICE
        let speechModelStore: SpeechModelStore
        let speechHistoryStore: SpeechHistoryStore
        let speechRecognitionService: SpeechRecognitionService
        #endif
    }

    private let windowCoordinator: AppWindowCoordinator
    private let dependencies: Dependencies

    init(windowCoordinator: AppWindowCoordinator, dependencies: Dependencies) {
        self.windowCoordinator = windowCoordinator
        self.dependencies = dependencies
    }

    func show(section: PreferenceSection? = nil, animated: Bool = true) {
        if let section {
            dependencies.navigation.selectedSection = section
        }

        windowCoordinator.showPreferences(
            title: L10n.windowPrefsTitle,
            animated: animated,
            makeContent: { [weak self] in
                guard let self else { return NSViewController() }
                return NSHostingController(rootView: makePreferencesView())
            }
        )
    }

    private func makePreferencesView() -> PreferencesView {
        let recordingHistoryContext = RecordingHistoryContext(
            store: dependencies.recordingStore,
            onDelete: { [weak self] artifact in
                self?.dependencies.recordingStore.delete(artifact)
            },
            onTrim: { [weak self] artifact in
                self?.dependencies.showRecordingTrimmer(artifact.fileURL)
            }
        )
        #if MEOW_VOICE
        return PreferencesView(
            viewModel: dependencies.viewModel,
            clipboardStore: dependencies.clipboardStore,
            navigation: dependencies.navigation,
            aiChatHistoryStore: dependencies.aiChatHistoryStore,
            keystrokeVisualizerService: dependencies.keystrokeVisualizerService,
            authenticatorService: dependencies.authenticatorService,
            healthReminderService: dependencies.healthReminderService,
            keepAwakeService: dependencies.keepAwakeService,
            speechModelStore: dependencies.speechModelStore,
            speechHistoryStore: dependencies.speechHistoryStore,
            speechRecognitionService: dependencies.speechRecognitionService,
            fileUploadService: dependencies.fileUploadService,
            makeCaptureHistoryView: dependencies.makeCaptureHistoryView,
            recordingHistoryContext: recordingHistoryContext
        )
        #else
        return PreferencesView(
            viewModel: dependencies.viewModel,
            clipboardStore: dependencies.clipboardStore,
            navigation: dependencies.navigation,
            aiChatHistoryStore: dependencies.aiChatHistoryStore,
            keystrokeVisualizerService: dependencies.keystrokeVisualizerService,
            authenticatorService: dependencies.authenticatorService,
            healthReminderService: dependencies.healthReminderService,
            keepAwakeService: dependencies.keepAwakeService,
            fileUploadService: dependencies.fileUploadService,
            makeCaptureHistoryView: dependencies.makeCaptureHistoryView,
            recordingHistoryContext: recordingHistoryContext
        )
        #endif
    }
}
