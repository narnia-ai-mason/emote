import EmoteCore
import XCTest

final class EmojiRecommendationPromptTests: XCTestCase {
  func testWordPromptIncludesToneAndOmitsJSONWhenGuided() {
    let prompt = EmojiRecommendationPrompt.userPrompt(
      query: RetrievalQuery(
        focus: "합격",
        context: "오늘 드디어 시험에 합격했어",
        tone: "따뜻하고 가볍게",
        kind: .word
      ),
      count: 5,
      asksForJSON: false
    )

    XCTAssertTrue(prompt.contains("Word: 합격"))
    XCTAssertTrue(prompt.contains("Sentence: 오늘 드디어 시험에 합격했어"))
    XCTAssertTrue(prompt.contains("Tone and style: 따뜻하고 가볍게"))
    XCTAssertFalse(prompt.contains("Return JSON only"))
    XCTAssertTrue(prompt.contains("from different categories"))
    XCTAssertTrue(prompt.contains("Never repeat a character"))
  }

  func testJSONPromptKeepsTheOpenRouterShape() {
    let prompt = EmojiRecommendationPrompt.userPrompt(
      query: RetrievalQuery(focus: "hello", kind: .sentence),
      count: 5,
      asksForJSON: true
    )

    XCTAssertTrue(prompt.contains("Sentence: hello"))
    XCTAssertTrue(
      prompt.contains(
        "Return JSON only in this shape: {\"emojis\":[\"<emoji>\",\"<emoji>\",\"<emoji>\"]}"
      )
    )
  }
}
