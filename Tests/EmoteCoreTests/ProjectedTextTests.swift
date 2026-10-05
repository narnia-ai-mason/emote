import EmoteCore
import XCTest

final class ProjectedTextTests: XCTestCase {
  // Slack and Chrome: marker text runs paragraphs together, AXValue keeps the breaks.
  private let marker = "NarniaLabs제조업을 위한 회사.설립: 2022년 4월본사: 대전\n미션 · 비전Mission: 세상."
  private let value = "NarniaLabs\n제조업을 위한 회사.\n설립: 2022년 4월\n본사: 대전\n\n미션 · 비전\nMission: 세상."

  func testMarkerTextTakesTheValuesLineBreaks() throws {
    let projection = try XCTUnwrap(ProjectedText.aligning(marker, onto: value))

    XCTAssertEqual(projection.text, value)
  }

  func testACaretInMarkerSpaceLandsOnTheSameCharacter() throws {
    let projection = try XCTUnwrap(ProjectedText.aligning(marker, onto: value))
    let caret = utf16(of: "미션", in: marker)
    let local = projection.local(caret..<caret)

    XCTAssertEqual(local.lowerBound, utf16(of: "미션", in: value))
    XCTAssertEqual(projection.source(local), caret..<caret)
  }

  func testACaretBetweenRunTogetherParagraphsEndsTheFirstUnlessItStartsTheNext() throws {
    let projection = try XCTUnwrap(ProjectedText.aligning(marker, onto: value))
    let caret = "NarniaLabs".utf16.count

    XCTAssertEqual(projection.local(caret..<caret), caret..<caret)
    XCTAssertEqual(projection.local(caret..<caret, afterBreak: true), (caret + 1)..<(caret + 1))
  }

  func testASelectionHugsItsWord() throws {
    let projection = try XCTUnwrap(ProjectedText.aligning(marker, onto: value))
    let lower = utf16(of: "세상", in: marker)
    let local = projection.local(lower..<(lower + 2))

    XCTAssertEqual(local, utf16(of: "세상", in: value)..<(utf16(of: "세상", in: value) + 2))
  }

  func testAValueCutShortIsNotALayout() {
    XCTAssertNil(ProjectedText.aligning(marker, onto: String(value.prefix(20))))
  }

  func testDifferentWordsAreNotALayout() {
    XCTAssertNil(ProjectedText.aligning("오늘 비가 왔다.", onto: "오늘 눈이 왔다."))
  }

  func testInvisibleCharactersAreDroppedAndTheCaretStillMaps() {
    let raw = "\n\u{FFFC}\u{200B}# NarniaLabs\n본문."
    let projection = ProjectedText(text: raw).removingInvisibles()
    let caret = utf16(of: "# Narnia", in: raw)

    XCTAssertEqual(projection.text, "\n# NarniaLabs\n본문.")
    XCTAssertEqual(projection.local(caret..<caret), 1..<1)
    XCTAssertEqual(projection.source(1..<1), caret..<caret)
  }

  func testAWindowCountsFromItsOrigin() {
    let projection = ProjectedText(text: "abc", origin: 10_000)

    XCTAssertEqual(projection.source(1..<2), 10_001..<10_002)
    XCTAssertEqual(projection.local(10_003..<10_003), 3..<3)
  }
}

private func utf16(of needle: String, in text: String) -> Int {
  text.utf16.distance(from: text.startIndex, to: text.range(of: needle)!.lowerBound)
}
