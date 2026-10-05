import EmoteCore
import XCTest

final class CaretReconcilerTests: XCTestCase {
  func testAColumnOnALaterLineIsNotTheStartOfThePage() {
    let text = "---\ntitle: '신발까지 다 젖었어'\n---\n\n> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.\"*"
    let lines = CaretReconciler.lineRanges(in: text)
    let quote = lines[4]
    let column = quote.count - 1

    let offset = CaretReconciler.caretOffset(column: column, on: quote, textLength: text.utf16.count)

    XCTAssertEqual(offset, quote.lowerBound + column)
    XCTAssertGreaterThan(offset ?? 0, lines[1].upperBound)
  }

  func testAnAbsoluteIndexAlreadyOnTheLineStaysPut() {
    let line = 120..<160
    XCTAssertEqual(
      CaretReconciler.caretOffset(column: 140, on: line, textLength: 400),
      140
    )
  }

  func testAPrefixOfTheFieldIsTheCaret() {
    let text = "---\ntitle: '신발까지 다 젖었어'\n> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.\""
    let prefix = "---\ntitle: '신발까지 다 젖었어'\n> *\"오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.\""
    XCTAssertEqual(CaretReconciler.caretOffset(prefix: prefix, in: text), text.utf16.count)
    XCTAssertNil(CaretReconciler.caretOffset(prefix: "지시문도", in: text))
  }

  func testChromiumsEmptyBoundsAreNotACaret() {
    let field = CGRect(x: -1884, y: -710, width: 737, height: 389)
    XCTAssertFalse(CaretReconciler.isPlausibleCaret(CGRect(x: -2257, y: -742, width: 0, height: 0), in: field))
    XCTAssertFalse(CaretReconciler.isPlausibleCaret(CGRect(x: 0, y: 1169, width: 0, height: 0), in: field))
  }

  func testACaretFarFromItsFieldIsRejected() {
    let field = CGRect(x: 100, y: 100, width: 400, height: 300)
    XCTAssertFalse(CaretReconciler.isPlausibleCaret(CGRect(x: 900, y: 900, width: 2, height: 16), in: field))
    XCTAssertTrue(CaretReconciler.isPlausibleCaret(CGRect(x: 240, y: 180, width: 0, height: 16), in: field))
  }

  func testAOneLineEditorHostStillHoldsItsCaret() {
    let host = CGRect(x: 1114, y: -1211, width: 1113, height: 18)
    XCTAssertTrue(CaretReconciler.isPlausibleCaret(CGRect(x: 1199, y: -1191, width: 0, height: 14), in: host))
  }

  func testAColumnPastTheLineIsRejected() {
    XCTAssertNil(CaretReconciler.caretOffset(column: 40, on: 0..<3, textLength: 80))
    XCTAssertNil(CaretReconciler.caretOffset(column: 4, on: 0..<10, textLength: 8))
  }
}
