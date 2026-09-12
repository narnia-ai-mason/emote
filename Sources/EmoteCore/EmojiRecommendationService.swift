import Foundation

public struct EmojiRecommendationService: Sendable {
  private static let recommendationCount = 5
  private let retriever: any EmojiCandidateRetrieving

  public init(retriever: any EmojiCandidateRetrieving) {
    self.retriever = retriever
  }

  public func recommend(
    for keyword: String,
    context: String? = nil,
    tone: String? = nil,
    kind: EmojiFocusKind? = nil,
    candidateHandler: (@Sendable ([ScoredEmojiCandidate]) -> Void)? = nil
  ) async throws -> EmojiRecommendations {
    let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      throw EmojiRecommendationError.emptyQuery
    }

    let context = context?.trimmingCharacters(in: .whitespacesAndNewlines)
    let tone = tone?.trimmingCharacters(in: .whitespacesAndNewlines)

    let retrieved = try await retriever.candidates(
      RetrievalQuery(
        focus: keyword,
        context: context,
        tone: tone?.isEmpty == false ? tone : nil,
        kind: kind ?? (context == nil ? .sentence : .word)
      ),
      limit: Self.recommendationCount
    )
    var seenEmoji = Set<String>()
    let candidates = retrieved.filter {
      seenEmoji.insert($0.recommendation.emoji).inserted
    }
    guard !candidates.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    let selected = Array(candidates.prefix(Self.recommendationCount))
    candidateHandler?(selected)

    return EmojiRecommendations(
      recommendations: selected.map(\.recommendation)
    )
  }
}
