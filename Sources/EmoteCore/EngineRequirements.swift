public enum EngineRequirements {
  public static func validate(
    engine: RecommendationEngine,
    apiKey: String,
    onDevice: OnDeviceModelStatus = .current
  ) throws {
    let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    switch engine {
    case .onDevice:
      guard onDevice.isAvailable else {
        throw EmojiRecommendationError.onDeviceUnavailable(onDevice.summary)
      }
    case .openRouter:
      guard hasKey else {
        throw EmojiRecommendationError.missingAPIKey
      }
    case .auto:
      guard onDevice.isAvailable || hasKey else {
        throw EmojiRecommendationError.notConfigured(
          "Turn on Apple Intelligence or add an OpenRouter API key."
        )
      }
    }
  }

  public static func isReady(
    engine: RecommendationEngine,
    apiKey: String,
    onDevice: OnDeviceModelStatus = .current
  ) -> Bool {
    (try? validate(engine: engine, apiKey: apiKey, onDevice: onDevice)) != nil
  }
}
