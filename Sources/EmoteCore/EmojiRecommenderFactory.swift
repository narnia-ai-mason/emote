public enum EmojiRecommenderFactory {
  public static func make(
    engine: RecommendationEngine,
    apiKey: String,
    model: String = OpenRouterEmojiRecommender.defaultModel,
    fallbackModels: [String] = OpenRouterEmojiRecommender.defaultFallbackModels,
    temperature: Double = OpenRouterEmojiRecommender.defaultTemperature,
    onDeviceTemperature: Double = AppleFoundationEmojiRecommender.defaultTemperature,
    memory: AutoRoutingMemory = .shared,
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) throws -> any EmojiCandidateRetrieving {
    _ = model
    _ = fallbackModels
    _ = temperature
    _ = onDeviceTemperature
    _ = memory
    _ = debugHandler
    try EngineRequirements.validate(engine: engine, apiKey: apiKey)
    throw EmojiRecommendationError.notConfigured(
      "Choose Gemma 4 or API in Settings."
    )
  }
}
