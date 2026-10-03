import EmoteCore
import XCTest

final class EngineRequirementsTests: XCTestCase {
  func testGemmaDoesNotNeedAnAPIKey() {
    XCTAssertNoThrow(
      try EngineRequirements.validate(engine: .gemma4, apiKey: "")
    )
  }

  func testAPINeedsAKey() {
    XCTAssertThrowsError(
      try EngineRequirements.validate(engine: .api, apiKey: "  ")
    ) { error in
      XCTAssertEqual(error as? EmojiRecommendationError, .missingAPIKey)
    }
    XCTAssertNoThrow(
      try EngineRequirements.validate(engine: .api, apiKey: "sk-test")
    )
  }
}

final class ChatAPIEndpointTests: XCTestCase {
  func testAVersionRootBecomesChatCompletions() throws {
    let url = try ChatAPIEndpoint.url(
      base: "https://api.openai.com/v1/",
      defaultBase: APIEmojiEngine.defaultBaseURL
    )
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testAFullCompletionsURLStaysPut() throws {
    let url = try ChatAPIEndpoint.url(
      base: "https://openrouter.ai/api/v1/chat/completions",
      defaultBase: APIEmojiEngine.defaultBaseURL
    )
    XCTAssertEqual(url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
  }

  func testAnEmptyBaseUsesTheDefault() throws {
    let url = try ChatAPIEndpoint.url(base: "  ", defaultBase: APIEmojiEngine.defaultBaseURL)
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }
}
