public enum RecommendationEngine: String, CaseIterable, Sendable {
  case gemma4
  case api

  public static let `default` = RecommendationEngine.gemma4

  public var title: String {
    switch self {
    case .gemma4:
      "Gemma 4"
    case .api:
      "API"
    }
  }
}
