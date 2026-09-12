import EmoteCore
import XCTest

final class EmojiRecommendationServiceTests: XCTestCase {
  func testReturnsTheFirstFiveOrderedCandidates() async throws {
    let result = try await EmojiRecommendationService(
      retriever: StubRetriever(values: Self.candidates)
    ).recommend(for: "안녕")

    XCTAssertEqual(
      result.recommendations.map(\.emoji),
      ["👋", "😀", "😊", "🙋", "🤝"]
    )
  }

  func testRemovesDuplicateEmojiAndKeepsTheNextCandidate() async throws {
    let duplicate = Self.candidate("👋", "Waving hand", score: 0.99)
    let result = try await EmojiRecommendationService(
      retriever: StubRetriever(values: [duplicate] + Self.candidates)
    ).recommend(for: "안녕")

    XCTAssertEqual(
      result.recommendations.map(\.emoji),
      ["👋", "😀", "😊", "🙋", "🤝"]
    )
  }

  func testAcceptsFewerThanFiveDistinctCandidates() async throws {
    let result = try await EmojiRecommendationService(
      retriever: StubRetriever(values: Array(Self.candidates.prefix(3)))
    ).recommend(for: "안녕")

    XCTAssertEqual(result.recommendations.map(\.emoji), ["👋", "😀", "😊"])
  }

  func testRejectsZeroCandidates() async {
    do {
      _ = try await EmojiRecommendationService(
        retriever: StubRetriever(values: [])
      ).recommend(for: "안녕")
      XCTFail("Expected the candidate count validation to fail")
    } catch {
      XCTAssertEqual(
        error as? EmojiRecommendationError,
        .insufficientCandidates(0)
      )
    }
  }

  func testRejectsAnEmptyKeywordBeforeRetrieval() async {
    do {
      _ = try await EmojiRecommendationService(
        retriever: StubRetriever(values: [])
      ).recommend(for: "   \n")
      XCTFail("Expected the empty keyword validation to fail")
    } catch {
      XCTAssertEqual(error as? EmojiRecommendationError, .emptyQuery)
    }
  }

  func testIncludesFocusedKeywordAndContextInRetrievalQuery() async throws {
    let recorder = QueryRecorder()
    _ = try await EmojiRecommendationService(
      retriever: RecordingRetriever(
        values: Self.candidates,
        recorder: recorder
      )
    ).recommend(
      for: " 합격 ",
      context: " 오늘 드디어 시험에 합격했어 "
    )

    let recorded = await recorder.query
    XCTAssertEqual(recorded?.focus, "합격")
    XCTAssertEqual(recorded?.context, "오늘 드디어 시험에 합격했어")
    XCTAssertEqual(recorded?.kind, .word)
  }

  func testPassesToneAndSentenceKind() async throws {
    let recorder = QueryRecorder()
    _ = try await EmojiRecommendationService(
      retriever: RecordingRetriever(
        values: Self.candidates,
        recorder: recorder
      )
    ).recommend(
      for: "오늘 드디어 시험에 합격했어",
      tone: " 따뜻하고 가볍게 ",
      kind: .sentence
    )

    let recorded = await recorder.query
    XCTAssertEqual(recorded?.kind, .sentence)
    XCTAssertEqual(recorded?.tone, "따뜻하고 가볍게")
    XCTAssertNil(recorded?.context)
  }

  private static let candidates = [
    candidate("👋", "Waving hand", score: 5),
    candidate("😀", "Grinning face", score: 4),
    candidate("😊", "Smiling face with smiling eyes", score: 3),
    candidate("🙋", "Person raising hand", score: 2),
    candidate("🤝", "Handshake", score: 1),
    candidate("🎉", "Party popper", score: 0),
  ]

  private static func candidate(
    _ emoji: String,
    _ description: String,
    score: Float
  ) -> ScoredEmojiCandidate {
    ScoredEmojiCandidate(
      recommendation: EmojiRecommendation(
        emoji: emoji,
        description: description
      ),
      score: score
    )
  }
}

private struct StubRetriever: EmojiCandidateRetrieving {
  let values: [ScoredEmojiCandidate]

  func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    values
  }
}

private actor QueryRecorder {
  private(set) var query: RetrievalQuery?

  func record(_ query: RetrievalQuery) {
    self.query = query
  }
}

private struct RecordingRetriever: EmojiCandidateRetrieving {
  let values: [ScoredEmojiCandidate]
  let recorder: QueryRecorder

  func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    await recorder.record(query)
    return Array(values.prefix(limit))
  }
}
