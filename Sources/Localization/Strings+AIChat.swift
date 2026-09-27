import Foundation

extension L10n {
    // MARK: - AI chat

    static var aiChatTitle: String {
        loc("ai.chat.title")
    }

    static var aiChatNoModel: String {
        loc("ai.chat.no.model")
    }

    static var aiChatHistoryTitle: String {
        loc("ai.chat.history.title")
    }

    static var aiChatHistoryEmpty: String {
        loc("ai.chat.history.empty")
    }

    static var aiChatNewConversation: String {
        loc("ai.chat.new.conversation")
    }

    static var aiChatDeleteConversation: String {
        loc("ai.chat.delete.conversation")
    }

    static var aiChatUntitledConversation: String {
        loc("ai.chat.untitled.conversation")
    }

    static var aiChatNotConfiguredTitle: String {
        loc("ai.chat.not.configured.title")
    }

    static var aiChatNotConfiguredSubtitle: String {
        loc("ai.chat.not.configured.subtitle")
    }

    static var aiChatOpenSettings: String {
        loc("ai.chat.open.settings")
    }

    static var aiChatEmptyTitle: String {
        loc("ai.chat.empty.title")
    }

    static var aiChatEmptySubtitle: String {
        loc("ai.chat.empty.subtitle")
    }

    static var aiChatInputPlaceholder: String {
        loc("ai.chat.input.placeholder")
    }

    static var aiChatYou: String {
        loc("ai.chat.you")
    }

    static var aiChatAssistant: String {
        loc("ai.chat.assistant")
    }

    static var aiChatCopy: String {
        loc("ai.chat.copy")
    }

    static var aiChatThinking: String {
        loc("ai.chat.thinking")
    }

    static var aiChatThinkingSection: String {
        loc("ai.chat.thinking.section")
    }

    static var aiChatPrivacyHint: String {
        loc("ai.chat.privacy.hint")
    }

    static var aiChatSend: String {
        loc("ai.chat.send")
    }

    static var aiClipboardPrompt: String {
        loc("ai.clipboard.prompt")
    }

    static var aiImagePrompt: String {
        loc("ai.image.prompt")
    }

    static var aiErrorNotConfigured: String {
        loc("ai.error.not.configured")
    }

    static var aiErrorInvalidEndpoint: String {
        loc("ai.error.invalid.endpoint")
    }

    static var aiErrorEmptyResponse: String {
        loc("ai.error.empty.response")
    }

    static func aiErrorRequestFailed(statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            return aiErrorRequestAuthorization
        case 429:
            return aiErrorRequestRateLimit
        case 500 ... 599:
            return aiErrorRequestServer
        default:
            return String(format: loc("ai.error.request.failed"), statusCode)
        }
    }

    static var aiErrorRequestAuthorization: String {
        loc("ai.error.request.authorization")
    }

    static var aiErrorRequestRateLimit: String {
        loc("ai.error.request.rate.limit")
    }

    static var aiErrorRequestServer: String {
        loc("ai.error.request.server")
    }

    static var aiErrorImageUnavailable: String {
        loc("ai.error.image.unavailable")
    }

    static var aiErrorAttachmentStorageLimitExceeded: String {
        loc("ai.error.attachment.storage.limit.exceeded")
    }

    static var aiErrorVisionUnsupported: String { loc("ai.error.vision.unsupported") }
    static var aiErrorVisionUnsupportedTitle: String { loc("ai.error.vision.unsupported.title") }
    static var aiImagePrivacyTitle: String { loc("ai.image.privacy.title") }
    static var aiImagePrivacyMessage: String { loc("ai.image.privacy.message") }
    static var aiImagePrivacyConfirm: String { loc("ai.image.privacy.confirm") }
    static var prefsAIVisionTitle: String { loc("prefs.ai.vision.title") }
    static var prefsAIVisionSubtitle: String { loc("prefs.ai.vision.subtitle") }
    static var prefsAIVisionPrivacy: String { loc("prefs.ai.vision.privacy") }
    static var prefsAIImageMaxDimension: String { loc("prefs.ai.image.max.dimension") }
    static var prefsAIImageQuality: String { loc("prefs.ai.image.quality") }
    static var prefsAIModelOpenSettings: String { loc("prefs.ai.model.open.settings") }

}
