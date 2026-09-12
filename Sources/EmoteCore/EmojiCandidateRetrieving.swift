public protocol EmojiCandidateRetrieving: Sendable {
  func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate]
}
