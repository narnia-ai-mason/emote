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
    try EngineRequirements.validate(engine: engine, apiKey: apiKey)
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let onDevice = AppleFoundationEmojiRecommender.makeIfAvailable(
      temperature: onDeviceTemperature,
      debugHandler: debugHandler
    )
    let openRouter: OpenRouterEmojiRecommender?
    if trimmedKey.isEmpty {
      openRouter = nil
    } else {
      openRouter = OpenRouterEmojiRecommender(
        client: OpenRouterClient(apiKey: trimmedKey),
        model: model,
        fallbackModels: fallbackModels,
        temperature: temperature,
        debugHandler: debugHandler
      )
    }

    switch engine {
    case .onDevice:
      guard let onDevice else {
        throw EmojiRecommendationError.onDeviceUnavailable(
          OnDeviceModelStatus.current.summary
        )
      }
      return onDevice
    case .openRouter:
      guard let openRouter else {
        throw EmojiRecommendationError.missingAPIKey
      }
      return openRouter
    case .auto:
      if onDevice == nil && openRouter == nil {
        throw EmojiRecommendationError.notConfigured(
          "Turn on Apple Intelligence or add an OpenRouter API key."
        )
      }
      return AutoEmojiRecommender(
        onDevice: onDevice,
        openRouter: openRouter,
        memory: memory,
        debugHandler: debugHandler
      )
    }
  }
}
