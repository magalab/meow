import Foundation

@MainActor
enum InternalInputEventSuppressor {
    private static var suppressedUntil = Date.distantPast

    static func suppress(for duration: TimeInterval) {
        suppressedUntil = max(suppressedUntil, Date().addingTimeInterval(duration))
    }

    static var isSuppressed: Bool {
        Date() < suppressedUntil
    }
}
