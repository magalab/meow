import SwiftUI

/// Invalidates a hosted SwiftUI surface when the app language changes without
/// replacing its identity, so local view state is preserved.
struct LocalizedRootView<Content: View>: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let _ = languageManager.refreshToken
        content()
    }
}
