public enum EngineRequirements {
  public static func validate(
    engine: RecommendationEngine,
    apiKey: String
  ) throws {
    switch engine {
    case .gemma4:
      break
    case .api:
      let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else {
        throw EmojiRecommendationError.missingAPIKey
      }
    }
  }

  public static func isReady(
    engine: RecommendationEngine,
    apiKey: String
  ) -> Bool {
    (try? validate(engine: engine, apiKey: apiKey)) != nil
  }
}
