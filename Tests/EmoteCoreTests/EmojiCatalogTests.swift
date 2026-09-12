import EmoteCore
import XCTest

final class EmojiCatalogTests: XCTestCase {
  func testUsesEnglishUnicodeNamesAndExcludesSkinToneVariants() {
    XCTAssertEqual(EmojiCatalog.name(for: "❤️"), "Red heart")
    XCTAssertFalse(EmojiCatalog.all.contains { $0.emoji == "👍🏻" })
  }

  func testMatchesVariationSelectorAndSkinToneVariantsToCanonicalEmoji() {
    let heart = EmojiCatalog.recommendation(matching: "❤")
    XCTAssertEqual(heart?.emoji, "❤️")
    XCTAssertEqual(heart?.description, "Red heart")

    let thumbsUp = EmojiCatalog.recommendation(matching: "👍🏻")
    XCTAssertEqual(thumbsUp?.emoji, "👍")
    XCTAssertEqual(thumbsUp?.description, "Thumbs up")
  }
}
