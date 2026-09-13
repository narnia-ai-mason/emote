public enum RecommendationEngine: String, CaseIterable, Sendable {
  case auto
  case onDevice
  case openRouter

  public static let `default` = RecommendationEngine.auto

  public var title: String {
    switch self {
    case .auto:
      "Auto"
    case .onDevice:
      "On-device"
    case .openRouter:
      "OpenRouter"
    }
  }
}
