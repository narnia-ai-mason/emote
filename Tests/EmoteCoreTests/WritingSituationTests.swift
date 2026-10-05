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

  func testMarkdownHeadingStripsTheMarkerAndKeepsTheNextSentence() {
    let text = "## 이직 준비\n다음 주 면접이 세 개다. 준비는 덜 됐다."
    let situation = WritingSituation.resolve(text: text, selectedUTF16: 0..<0, tone: "dry")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(situation?.span, "이직 준비")
    XCTAssertEqual(
      situation?.message,
      """
      <heading>이직 준비</heading>
      <next-sentence>다음 주 면접이 세 개다.</next-sentence>
      <tone>dry</tone>
      """
    )
  }

  func testMarkdownHeadingWithAPeriodStaysAHeadingWhenTheCaretIsInsideIt() {
    let text = "# 끝났다.\n본문은 여기다."
    let caret = utf16Offset(after: "# 끝났", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(situation?.span, "끝났다.")
    XCTAssertTrue(situation?.message.contains("<next-sentence>본문은 여기다.</next-sentence>") == true)
  }

  func testClosedAndIndentedMarkdownHeadingsStripTheMarker() {
    let closed = WritingSituation.resolve(text: "## 이직 준비 ##", selectedUTF16: 0..<0, tone: "neutral")
    XCTAssertEqual(closed?.span, "이직 준비")

    let indented = "   ###### 이직 준비"
    let caret = utf16Offset(after: "   ###### 이직", in: indented)
    let situation = WritingSituation.resolve(
      text: indented,
      selectedUTF16: caret..<caret,
      tone: "neutral"
    )
    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(situation?.span, "이직 준비")
  }

  func testSetextHeadingSkipsTheUnderline() {
    let text = "이직 준비\n=========\n다음 주 면접이 세 개다. 준비는 덜 됐다."
    let atTitle = WritingSituation.resolve(text: text, selectedUTF16: 0..<0, tone: "dry")
    XCTAssertEqual(atTitle?.mode, .heading)
    XCTAssertEqual(atTitle?.span, "이직 준비")
    XCTAssertTrue(
      atTitle?.message.contains("<next-sentence>다음 주 면접이 세 개다.</next-sentence>") == true
    )

    let underline = utf16Offset(of: "=========", in: text)
    let onUnderline = WritingSituation.resolve(
      text: text,
      selectedUTF16: underline..<underline,
      tone: "dry"
    )
    XCTAssertEqual(onUnderline?.message, atTitle?.message)
  }

  func testAsciiDocAndHTMLHeadingsUseTheTitle() {
    let asciidoc = WritingSituation.resolve(
      text: "= 이직 준비\n다음 주 면접이 세 개다.",
      selectedUTF16: 0..<0,
      tone: "neutral"
    )
    XCTAssertEqual(asciidoc?.mode, .heading)
    XCTAssertEqual(asciidoc?.span, "이직 준비")

    let html = WritingSituation.resolve(
      text: "<h2>이직 준비</h2>\n다음 주 면접이 세 개다.",
      selectedUTF16: 0..<0,
      tone: "neutral"
    )
    XCTAssertEqual(html?.span, "이직 준비")
    XCTAssertTrue(html?.message.contains("<next-sentence>다음 주 면접이 세 개다.</next-sentence>") == true)
  }

  func testAHashWithoutTheMarkdownSpaceStaysASentenceWhenItEnds() {
    let glued = WritingSituation.resolve(text: "#끝났다.", selectedUTF16: 0..<0, tone: "neutral")
    XCTAssertEqual(glued?.mode, .sentence)
    XCTAssertEqual(glued?.span, "#끝났다.")

    let tooMany = WritingSituation.resolve(text: "####### 끝났다.", selectedUTF16: 0..<0, tone: "neutral")
    XCTAssertEqual(tooMany?.mode, .sentence)

    let codeIndent = WritingSituation.resolve(
      text: "    # 끝났다.",
      selectedUTF16: 0..<0,
      tone: "neutral"
    )
    XCTAssertEqual(codeIndent?.mode, .sentence)
  }

  func testAHashInsideASentenceDoesNotForceHeadingMode() {
    let text = "오늘 신발 #참고"
    let caret = utf16Offset(after: "오늘 신발", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .word)
    XCTAssertEqual(situation?.span, "신발")
  }

  func testAnEmptyMarkdownHeadingWithNothingAfterItResolvesToNothing() {
    let situation = WritingSituation.resolve(text: "#", selectedUTF16: 0..<0, tone: nil)
    XCTAssertNil(situation)
  }

  func testAThematicBreakIsNotAHeading() {
    let text = "---\ntitle: '신발까지 다 젖었어'"
    let situation = WritingSituation.resolve(text: text, selectedUTF16: 0..<0, tone: "neutral")

    XCTAssertNotEqual(situation?.mode, .heading)
    XCTAssertFalse(situation?.message.contains("<heading>---</heading>") == true)
  }

  func testCaretBetweenAClosingQuoteAndEmphasisUsesTheSentence() {
    let text = "> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.\"*"
    let caret = utf16Offset(of: ".\"*", in: text) + ".\"".utf16.count
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(
      situation?.message,
      """
      <sentence>오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.</sentence>
      <tone>neutral</tone>
      """
    )
  }

  func testMarkdownHeadingSkipsTheBlankLineBeforeItsParagraph() {
    let text = "updated: 2026-05-28\n---\n\n# NarniaLabs\n\n제조업을 위한 generative AI 회사. 자사 플랫폼이다."
    let caret = utf16Offset(after: "# ", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(situation?.span, "NarniaLabs")
    XCTAssertTrue(
      situation?.message.contains("<next-sentence>제조업을 위한 generative AI 회사.</next-sentence>") == true
    )
  }

  func testAPlainHeadingSkipsBlankLinesToo() {
    let text = "이직 준비\n\n\n다음 주 면접이 세 개다."
    let situation = WritingSituation.resolve(text: text, selectedUTF16: 0..<0, tone: "neutral")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertTrue(situation?.message.contains("<next-sentence>다음 주 면접이 세 개다.</next-sentence>") == true)
  }

  func testAHeadingDirectlyAboveAnotherHeadingHasNoNextSentence() {
    let text = "## 연혁 · 투자\n\n### 2021\n\nKAIST E5 랩 창업."
    let situation = WritingSituation.resolve(text: text, selectedUTF16: 3..<3, tone: "neutral")

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertTrue(situation?.message.contains("<next-sentence></next-sentence>") == true)
  }

  func testAHeadingAloneInItsBlockTakesTheNextBlocksSentence() {
    let situation = WritingSituation.resolve(
      text: "미션 · 비전",
      selectedUTF16: 0..<0,
      tone: "neutral",
      following: "Mission: 누구나 AI로 최고의 제품을 설계할 수 있는 세상. Vision: 세계 최고의 AI 회사."
    )

    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(
      situation?.message,
      """
      <heading>미션 · 비전</heading>
      <next-sentence>Mission: 누구나 AI로 최고의 제품을 설계할 수 있는 세상.</next-sentence>
      <tone>neutral</tone>
      """
    )
  }

  func testTheNextBlockDoesNotReplaceANextLineInTheSameField() {
    let situation = WritingSituation.resolve(
      text: "이직 준비\n다음 주 면접이 세 개다.",
      selectedUTF16: 0..<0,
      tone: "neutral",
      following: "다른 블록이다."
    )

    XCTAssertTrue(situation?.message.contains("<next-sentence>다음 주 면접이 세 개다.</next-sentence>") == true)
  }

  func testAnEmojiAfterThePeriodStaysWithItsSentence() {
    let text = "> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어. 😩\"* \n\n설치 파일은 여기."
    let caret = utf16Offset(after: "😩\"* ", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(situation?.span, "오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어. 😩\"*")
  }

  func testClosingMarkupAfterASpaceIsNotAHeading() {
    let text = "> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어. \"* \n\n설치 파일은 여기."
    let caret = utf16Offset(after: "젖었어. ", in: text)
    let situation = WritingSituation.resolve(text: text, selectedUTF16: caret..<caret, tone: "neutral")

    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(situation?.span, "오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.")
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
