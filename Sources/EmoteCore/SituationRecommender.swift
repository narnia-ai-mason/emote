import Foundation

public struct RankedEmoji: Equatable, Sendable {
  public var emoji: String
  public var score: Double

  public init(emoji: String, score: Double) {
    self.emoji = emoji
    self.score = score
  }
}

public struct SituationOutcome: Equatable, Sendable {
  public enum Stage: String, Equatable, Sendable {
    case cldr
    case embedding
    case onDevice
  }

  public var stage: Stage
  public var recommendations: [EmojiRecommendation]
  public var embedding: [RankedEmoji]

  public init(
    stage: Stage,
    recommendations: [EmojiRecommendation],
    embedding: [RankedEmoji] = []
  ) {
    self.stage = stage
    self.recommendations = recommendations
    self.embedding = embedding
  }
}

public struct SituationRecommender: Sendable {
  public var rank: (@Sendable (String) async -> [RankedEmoji])?
  public var minimumEmbeddingScore: Double
  public var minimumEmbeddingGap: Double
  public var cldr: CldrKeywordIndex

  public init(
    cldr: CldrKeywordIndex = .loadBundled(),
    rank: (@Sendable (String) async -> [RankedEmoji])? = nil,
    minimumEmbeddingScore: Double = 0.84,
    minimumEmbeddingGap: Double = 0.015
  ) {
    self.cldr = cldr
    self.rank = rank
    self.minimumEmbeddingScore = minimumEmbeddingScore
    self.minimumEmbeddingGap = minimumEmbeddingGap
  }

  public func recommend(_ situation: WritingSituation) async throws -> SituationOutcome {
    if situation.usesWordCascade, let emojis = cldr.match(tokens: situation.tokens) {
      let recommendations = catalogMatches(emojis)
      if !recommendations.isEmpty {
        return SituationOutcome(stage: .cldr, recommendations: recommendations)
      }
    }

    var embedding: [RankedEmoji] = []
    if situation.usesWordCascade, let rank {
      embedding = await rank(situation.span)
      if accepts(embedding) {
        let recommendations = catalogMatches(embedding.map(\.emoji))
        if !recommendations.isEmpty {
          return SituationOutcome(
            stage: .embedding,
            recommendations: recommendations,
            embedding: embedding
          )
        }
      }
    }

    guard #available(macOS 26.0, *) else {
      throw EmojiRecommendationError.onDeviceUnavailable(
        OnDeviceModelStatus.unsupportedOS.summary
      )
    }
    let raw = try await AppleFoundationEmojiRecommender.complete(
      instructions: situation.instructions,
      prompt: situation.message
    )
    let recommendations = catalogMatches(raw)
    guard !recommendations.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    return SituationOutcome(
      stage: .onDevice,
      recommendations: recommendations,
      embedding: embedding
    )
  }

  private func accepts(_ ranked: [RankedEmoji]) -> Bool {
    guard let best = ranked.first, best.score >= minimumEmbeddingScore else { return false }
    let later = ranked.dropFirst(4).first?.score ?? best.score
    return best.score - later >= minimumEmbeddingGap
  }

  private func catalogMatches(_ emojis: [String]) -> [EmojiRecommendation] {
    var seen = Set<String>()
    var results: [EmojiRecommendation] = []
    for emoji in emojis {
      guard
        let recommendation = EmojiCatalog.recommendation(matching: emoji),
        seen.insert(recommendation.emoji).inserted
      else { continue }
      results.append(recommendation)
      if results.count == 10 { break }
    }
    return results
  }
}
