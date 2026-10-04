import EmoteCore
import XCTest

final class WritingSituationTests: XCTestCase {
  func testDocumentStartIsAHeadingAndKeepsOnlyTheNextLinesFirstSentence() {
    let text = "이직 준비\n다음 주 면접이 세 개다. 준비는 덜 됐다."
    let situation = WritingSituation.resolve(text: text, selectedUTF16: 0..<0, tone: "dry")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(
      situation?.message,
      """
      <heading>이직 준비</heading>
      <next-sentence>다음 주 면접이 세 개다.</next-sentence>
      <tone>dry</tone>
      """
    )
    XCTAssertEqual(situation?.instructions, WritingSituation.headingInstructions)
  }

  func testCaretAtTheStartOfALaterHeadingUsesThatLine() {
    let text = "어제 메모.\n이직 준비\n다음 주 면접이 세 개다. 준비는 덜 됐다."
    let caret = utf16Offset(of: "이직 준비", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "dry")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(
      situation?.message,
      """
      <heading>이직 준비</heading>
      <next-sentence>다음 주 면접이 세 개다.</next-sentence>
      <tone>dry</tone>
      """
    )
  }

  func testAPunctuatedSentenceAtItsStartStaysASentence() {
    let text = "어제 메모.\n오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.\n끝."
    let caret = utf16Offset(of: "오늘 퇴근길", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "dry")

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(situation?.span, "오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.")
  }

  func testASavedJoyfulToneBecomesPlayful() {
    let situation = WritingSituation.resolve(text: "이직 준비", selectedUTF16: 0..<0, tone: "joyful")

    XCTAssertTrue(situation?.message.contains("<tone>playful</tone>") == true)
  }

  func testAnUnknownToneBecomesNeutral() {
    let situation = WritingSituation.resolve(text: "이직 준비", selectedUTF16: 0..<0, tone: "warm and light")

    XCTAssertTrue(situation?.message.contains("<tone>neutral</tone>") == true)
  }

  func testHeadingWithoutAFollowingLineLeavesTheNextSentenceEmpty() {
    let situation = WritingSituation.resolve(text: "이직 준비", selectedUTF16: 0..<0, tone: nil)

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertTrue(situation?.message.contains("<next-sentence></next-sentence>") == true)
    XCTAssertTrue(situation?.message.contains("<tone>neutral</tone>") == true)
  }

  func testCaretAfterAPeriodSendsTheSentenceBeforeIt() {
    let text = "오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어."
    let caret = text.utf16.count
    let situation = WritingSituation.resolve(
      text: text,
      selectedUTF16: caret..<caret,
      tone: "dry"
    )

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(
      situation?.message,
      """
      <sentence>오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.</sentence>
      <tone>dry</tone>
      """
    )
  }

  func testCaretAfterASpaceSendsTheSentenceSoFar() {
    let text = "오늘 비가 왔다. 신발도 젖었다"
    let caret = utf16Offset(after: "오늘 비가 ", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "dry")

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(situation?.span, "오늘 비가")
  }

  func testCaretGluedToAWordUsesThatWord() {
    let text = "오늘 신발"
    let caret = utf16Offset(after: "오늘 신발", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .word)
    XCTAssertEqual(situation?.span, "신발")
    XCTAssertTrue(situation?.message.contains("<word>신발</word>") == true)
  }

  func testShortSelectionStaysOnTheWordCascade() {
    let text = "어제 젖은 신발을 말렸다"
    let start = utf16Offset(of: "젖은 신발", in: text)
    let end = start + "젖은 신발".utf16.count
    let situation = WritingSituation.resolve(text: text, selectedUTF16: start..<end, tone: "neutral")

    XCTAssertEqual(situation?.mode, .word)
    XCTAssertEqual(situation?.span, "젖은 신발")
    XCTAssertTrue(situation?.message.contains("<sentence>어제 젖은 신발을 말렸다</sentence>") == true)
  }

  func testSentenceShapedSelectionUsesTheSentenceRequest() {
    let text = "오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어."
    let situation = WritingSituation.resolve(
      text: text,
      selectedUTF16: 0..<text.utf16.count,
      tone: "dry"
    )

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertTrue(situation?.message.hasPrefix("<sentence>") == true)
  }
}

private func utf16Offset(of needle: String, in text: String) -> Int {
  let haystack = Array(text.utf16)
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
