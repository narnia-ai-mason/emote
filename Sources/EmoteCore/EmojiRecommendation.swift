import Foundation

public struct EmojiRecommendation: Codable, Equatable, Sendable {
  public let emoji: String
  public let description: String

  public init(emoji: String, description: String) {
    self.emoji = emoji
    self.description = description
  }
}

public enum EmojiFocusKind: Equatable, Sendable {
  case sentence
  case word
}

public enum EmojiRecommendationError: Error, Equatable, LocalizedError {
  case insufficientCandidates(Int)
  case missingAPIKey
  case notConfigured(String)
  case emptyModelResponse
  case requestFailed(String)

  public var errorDescription: String? {
    switch self {
    case .insufficientCandidates(let count):
      "Expected at least 5 distinct candidates, but retrieved \(count)."
    case .missingAPIKey:
      "Set EMOTE_API_KEY or OPENAI_API_KEY."
    case .notConfigured(let detail):
      detail
    case .emptyModelResponse:
      "The model returned an empty response."
    case .requestFailed(let detail):
      detail
    }
  }
}
