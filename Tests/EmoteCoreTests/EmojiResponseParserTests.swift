import XCTest

@testable import EmoteCore

final class EmojiResponseParserTests: XCTestCase {
  func testReadsEmojisFromJSONObject() {
    let content = """
      ```json
      {"emojis":["🎉","🎓","✨","🥳","👏"]}
      ```
      """

    XCTAssertEqual(
      EmojiResponseParser.recommendations(from: content, limit: 5).map(\.emoji),
      ["🎉", "🎓", "✨", "🥳", "👏"]
    )
  }

  func testReadsEmojisFromRecommendationObjectsAndDropsUnknownTokens() {
    let content = """
      {"recommendations":[{"emoji":"💡"},{"emoji":"not-an-emoji"},{"emoji":"🧠"}]}
      """

    XCTAssertEqual(
      EmojiResponseParser.recommendations(from: content, limit: 5).map(\.emoji),
      ["💡", "🧠"]
    )
  }

  func testFallsBackToCatalogMatchesWhenJSONIsMissing() {
    let content = "Maybe 🌧️ or 💡 would work here."

    XCTAssertEqual(
      EmojiResponseParser.recommendations(from: content, limit: 5).map(\.emoji),
      ["🌧️", "💡"]
    )
  }
}
