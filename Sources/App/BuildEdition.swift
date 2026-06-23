enum BuildEdition {
    #if MEOW_VOICE
    static let includesVoiceFeatures = true
    static let productName = "Miao"
    #else
    static let includesVoiceFeatures = false
    static let productName = "Meow"
    #endif
}
