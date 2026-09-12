import EmoteCore
import XCTest

final class TextFocusTests: XCTestCase {
  func testSentenceStartRecommendsTheWholeSentence() {
    let text = "오늘 드디어 시험에 합격했어"
    let focus = TextFocus.resolve(text: text, selectedUTF16: 0..<0)

    XCTAssertEqual(focus?.kind, .sentence)
    XCTAssertEqual(focus?.focus, text)
    XCTAssertEqual(focus?.insertion, .insert(utf16: 0))
  }

  func testCursorAfterASentenceTerminatorStartsTheNextSentence() {
    let text = "끝났어. 이제 시작이야"
    let cursor = utf16Offset(of: "이제", in: text)
    let focus = TextFocus.resolve(text: text, selectedUTF16: cursor..<cursor)

    XCTAssertEqual(focus?.kind, .sentence)
    XCTAssertEqual(focus?.focus, "이제 시작이야")
  }

  func testCursorAfterAWordUsesThatWordAndTheSentence() {
    let text = "오늘 드디어 시험에 합격했어"
    let cursor = utf16Offset(after: "합격", in: text)
    let focus = TextFocus.resolve(text: text, selectedUTF16: cursor..<cursor)

    XCTAssertEqual(focus?.kind, .word)
    XCTAssertEqual(focus?.focus, "합격했어")
    XCTAssertEqual(focus?.sentence, text)
    XCTAssertEqual(focus?.insertion, .insert(utf16: cursor))
    let wordStart = utf16Offset(of: "합격했어", in: text)
    XCTAssertEqual(focus?.anchorUTF16, wordStart..<(wordStart + "합격했어".utf16.count))
  }

  func testCursorAfterASpaceStillUsesThePreviousWord() {
    let text = "hello world"
    let cursor = utf16Offset(after: "hello ", in: text)
    let focus = TextFocus.resolve(text: text, selectedUTF16: cursor..<cursor)

    XCTAssertEqual(focus?.kind, .word)
    XCTAssertEqual(focus?.focus, "hello")
    XCTAssertEqual(focus?.insertion, .insert(utf16: cursor))
  }

  func testSelectionReplacesTheSelectedWord() {
    let text = "오늘 드디어 시험에 합격했어"
    let start = utf16Offset(of: "합격", in: text)
    let end = start + "합격".utf16.count
    let focus = TextFocus.resolve(text: text, selectedUTF16: start..<end)

    XCTAssertEqual(focus?.kind, .word)
    XCTAssertEqual(focus?.focus, "합격")
    XCTAssertEqual(focus?.sentence, text)
    XCTAssertEqual(focus?.insertion, .replace(utf16: start..<end))
  }

  func testEmptyTextReturnsNil() {
    XCTAssertNil(TextFocus.resolve(text: "   ", selectedUTF16: 0..<0))
  }
}

private func utf16Offset(of needle: String, in text: String) -> Int {
  let view = text.utf16
  let haystack = Array(view)
  let needleUnits = Array(needle.utf16)
  for start in 0...(haystack.count - needleUnits.count) {
    if haystack[start..<(start + needleUnits.count)].elementsEqual(needleUnits) {
      return start
    }
  }
  return 0
}

private func utf16Offset(after prefix: String, in text: String) -> Int {
  utf16Offset(of: prefix, in: text) + prefix.utf16.count
}
