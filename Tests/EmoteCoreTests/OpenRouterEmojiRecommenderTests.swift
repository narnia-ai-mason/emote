import EmoteCore
import XCTest

final class OpenRouterEmojiRecommenderTests: XCTestCase {
  func testMapsModelJSONToCatalogNamesAndScores() async throws {
    let client = StubChatClient(
      responses: [
        ChatCompletionResponse(
          model: "google/gemma-4-31b-it:free",
          content: #"{"emojis":["🎉","🎓","✨","🥳","👏"]}"#
        )
      ]
    )
    let result = try await OpenRouterEmojiRecommender(
      client: client
    ).candidates(
      RetrievalQuery(
        focus: "합격",
        context: "오늘 드디어 시험에 합격했어",
        tone: "따뜻하고 가볍게",
        kind: .word
      ),
      limit: 5
    )

    XCTAssertEqual(result.map(\.recommendation.emoji), ["🎉", "🎓", "✨", "🥳", "👏"])
    XCTAssertEqual(result.map(\.recommendation.description), [
      "Party popper",
      "Graduation cap",
      "Sparkles",
      "Partying face",
      "Clapping hands",
    ])
    XCTAssertEqual(result.map(\.score), [5, 4, 3, 2, 1])
    XCTAssertTrue(client.requests[0].messages[1].content.contains("Word: 합격"))
    XCTAssertTrue(client.requests[0].messages[1].content.contains("Sentence: 오늘 드디어 시험에 합격했어"))
    XCTAssertTrue(client.requests[0].messages[1].content.contains("Tone and style: 따뜻하고 가볍게"))
    XCTAssertTrue(client.requests[0].messages[1].content.contains("Suggest 5 distinct"))
  }

  func testKeepsAPartialFirstResponseWithoutASecondRoundTrip() async throws {
    let client = StubChatClient(
      responses: [
        ChatCompletionResponse(model: "test", content: #"{"emojis":["🎉"]}"#),
        ChatCompletionResponse(
          model: "test",
          content: #"{"emojis":["🎓","✨","🥳","👏"]}"#
        ),
      ]
    )
    let result = try await OpenRouterEmojiRecommender(
      client: client
    ).candidates(RetrievalQuery(focus: "합격", kind: .word), limit: 5)

    XCTAssertEqual(client.requests.count, 1)
    XCTAssertTrue(client.requests[0].disableReasoning)
    XCTAssertEqual(result.map(\.recommendation.emoji), ["🎉"])
  }

  func testRetriesWhenTheFirstResponseHasNoCatalogEmojis() async throws {
    let client = StubChatClient(
      responses: [
        ChatCompletionResponse(model: "test", content: #"{"emojis":["not-an-emoji"]}"#),
        ChatCompletionResponse(
          model: "test",
          content: #"{"emojis":["🎉","🎓","✨","🥳","👏"]}"#
        ),
      ]
    )
    let result = try await OpenRouterEmojiRecommender(
      client: client
    ).candidates(RetrievalQuery(focus: "합격", kind: .word), limit: 5)

    XCTAssertEqual(client.requests.count, 2)
    XCTAssertEqual(result.map(\.recommendation.emoji), ["🎉", "🎓", "✨", "🥳", "👏"])
  }

  func testFallsBackToTheNextModelWhenThePrimaryRequestFails() async throws {
    let client = StubChatClient(
      responses: [
        ChatCompletionResponse(
          model: "openrouter/free",
          content: #"{"emojis":["🎉","🎓","✨","🥳","👏"]}"#
        )
      ],
      error: EmojiRecommendationError.requestFailed("HTTP 403: privacy"),
      failFirst: true
    )
    let result = try await OpenRouterEmojiRecommender(
      client: client,
      model: "google/gemma-4-31b-it:free",
      fallbackModels: ["openrouter/free"]
    ).candidates(RetrievalQuery(focus: "합격", kind: .word), limit: 5)

    XCTAssertEqual(client.requests.map(\.model), [
      "google/gemma-4-31b-it:free",
      "openrouter/free",
    ])
    XCTAssertEqual(result.map(\.recommendation.emoji), ["🎉", "🎓", "✨", "🥳", "👏"])
  }

  func testReturnsNothingWhenRetryAfterAnEmptyParseFails() async throws {
    let client = StubChatClient(
      responses: [
        ChatCompletionResponse(model: "test", content: #"{"emojis":[]}"#)
      ],
      error: EmojiRecommendationError.emptyModelResponse
    )
    let result = try await OpenRouterEmojiRecommender(
      client: client
    ).candidates(RetrievalQuery(focus: "합격", kind: .word), limit: 5)

    XCTAssertEqual(client.requests.count, 2)
    XCTAssertEqual(result.map(\.recommendation.emoji), [])
  }

  func testRecommendedModelsAreTheWorkingFreeDefaults() {
    XCTAssertEqual(
      OpenRouterEmojiRecommender.recommendedModels,
      ["openrouter/free", "nex-agi/nex-n2.5-mini:free"]
    )
  }

  func testLiveFactoryUsesDefaultModelWhenNoneIsConfigured() throws {
    let recommender = try OpenRouterEmojiRecommender.live(
      environment: ["OPENROUTER_API_KEY": "sk-test"]
    )
    XCTAssertEqual(recommender.model, OpenRouterEmojiRecommender.defaultModel)
    XCTAssertEqual(recommender.fallbackModels, [])
  }

  func testLiveFactoryRequiresAnAPIKey() {
    XCTAssertThrowsError(
      try OpenRouterEmojiRecommender.live(environment: [:])
    ) { error in
      XCTAssertEqual(error as? EmojiRecommendationError, .missingAPIKey)
    }
  }

  func testLiveFactoryUsesAnyConfiguredModelAndFallbacks() throws {
    let recommender = try OpenRouterEmojiRecommender.live(
      environment: [
        "OPENROUTER_API_KEY": "sk-test",
        "OPENROUTER_MODEL": "openai/gpt-4.1-mini",
        "OPENROUTER_FALLBACK_MODELS": "google/gemma-4-31b-it:free, openrouter/free",
      ]
    )
    XCTAssertEqual(recommender.model, "openai/gpt-4.1-mini")
    XCTAssertEqual(
      recommender.fallbackModels,
      ["google/gemma-4-31b-it:free", "openrouter/free"]
    )
  }
}

private final class StubChatClient: ChatCompleting, @unchecked Sendable {
  private var remaining: [ChatCompletionResponse]
  private let error: Error?
  private let failFirst: Bool
  private(set) var requests: [ChatCompletionRequest] = []

  init(
    responses: [ChatCompletionResponse],
    error: Error? = nil,
    failFirst: Bool = false
  ) {
    remaining = responses
    self.error = error
    self.failFirst = failFirst
  }

  func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
    requests.append(request)
    if failFirst && requests.count == 1 {
      throw error ?? EmojiRecommendationError.emptyModelResponse
    }
    if remaining.isEmpty {
      throw error ?? EmojiRecommendationError.emptyModelResponse
    }
    return remaining.removeFirst()
  }
}
