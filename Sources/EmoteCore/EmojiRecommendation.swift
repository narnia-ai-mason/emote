import Foundation

public struct EmojiRecommendation: Codable, Equatable, Sendable {
  public let emoji: String
  public let description: String

  public init(emoji: String, description: String) {
    self.emoji = emoji
    self.description = description
  }
}

public struct EmojiRecommendations: Codable, Equatable, Sendable {
  public let recommendations: [EmojiRecommendation]

  public init(recommendations: [EmojiRecommendation]) {
    self.recommendations = recommendations
  }
}

public enum EmojiFocusKind: Equatable, Sendable {
  case sentence
  case word
}

public struct RetrievalQuery: Equatable, Sendable {
  public var focus: String
  public var context: String?
  public var tone: String?
  public var kind: EmojiFocusKind

  public init(
    focus: String,
    context: String? = nil,
    tone: String? = nil,
    kind: EmojiFocusKind
  ) {
    self.focus = focus
    self.context = context
    self.tone = tone
    self.kind = kind
  }
}

public struct ScoredEmojiCandidate: Equatable, Sendable {
  public let recommendation: EmojiRecommendation
  public let score: Float

  public init(recommendation: EmojiRecommendation, score: Float) {
    self.recommendation = recommendation
    self.score = score
  }
}

public enum EmojiRecommendationError: Error, Equatable, LocalizedError {
  case emptyQuery
  case insufficientCandidates(Int)
  case missingAPIKey
  case emptyModelResponse
  case invalidModelResponse(String)
  case requestFailed(String)

  public var errorDescription: String? {
    switch self {
    case .emptyQuery:
      "Keyword must not be empty."
    case .insufficientCandidates(let count):
      "Expected at least 5 distinct candidates, but retrieved \(count)."
    case .missingAPIKey:
      "Set OPENROUTER_API_KEY in the environment or a .env file."
    case .emptyModelResponse:
      "The model returned an empty response."
    case .invalidModelResponse(let detail):
      "The model response could not be parsed: \(detail)"
    case .requestFailed(let detail):
      detail
    }
  }
}
