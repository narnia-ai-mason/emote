import EmoteCore
import XCTest

final class NeovimStateTests: XCTestCase {
  private let lines = ["# NarniaLabs", "", "제조업을 위한 회사. 세상을 바꾼다."]

  func testInsertModesCaretSitsBeforeTheCursorByte() {
    let byte = "제조업을".utf8.count
    let state = NeovimState(mode: "i", lines: lines, line: 3, col: byte)

    XCTAssertEqual(state.selectedUTF16, offset(of: " 위한")..<offset(of: " 위한"))
  }

  func testNormalModeOnTheHeadingsFirstCharacterIsBeforeIt() {
    let state = NeovimState(mode: "n", lines: lines, line: 1, col: 0)
    let situation = WritingSituation.resolve(text: state.text, selectedUTF16: state.selectedUTF16, tone: nil)

    XCTAssertEqual(state.selectedUTF16, 0..<0)
    XCTAssertEqual(situation?.mode, .heading)
    XCTAssertEqual(situation?.span, "NarniaLabs")
  }

  func testNormalModeOnASentencesPeriodIsAfterIt() {
    let byte = "제조업을 위한 회사".utf8.count
    let state = NeovimState(mode: "n", lines: lines, line: 3, col: byte)
    let situation = WritingSituation.resolve(text: state.text, selectedUTF16: state.selectedUTF16, tone: nil)

    XCTAssertEqual(state.selectedUTF16.lowerBound, offset(of: " 세상"))
    XCTAssertEqual(situation?.mode, .sentence)
    XCTAssertEqual(situation?.span, "제조업을 위한 회사.")
  }

  func testCharacterwiseVisualIncludesTheCharacterUnderTheCursor() {
    let start = "제조업을 위한 회사. ".utf8.count
    let end = "제조업을 위한 회사. 세".utf8.count
    let state = NeovimState(mode: "v", lines: lines, line: 3, col: end, vline: 3, vcol: start)
    let lower = offset(of: "세상")

    XCTAssertEqual(state.selectedUTF16, lower..<(lower + 2))
  }

  func testVisualWorksWhenTheCursorIsBeforeItsOtherEnd() {
    let start = "제조업을 위한 회사. ".utf8.count
    let state = NeovimState(mode: "v", lines: lines, line: 3, col: start, vline: 3, vcol: start + "세".utf8.count)
    let lower = offset(of: "세상")

    XCTAssertEqual(state.selectedUTF16, lower..<(lower + 2))
  }

  func testLinewiseVisualSelectsWholeLines() {
    let state = NeovimState(mode: "V", lines: lines, line: 3, col: 5, vline: 3, vcol: 0)
    let text = state.text as NSString

    XCTAssertEqual(text.substring(with: NSRange(state.selectedUTF16)), lines[2])
  }

  func testPositionsMapBackToBufferBytes() {
    let state = NeovimState(mode: "i", first: 40, lines: lines, line: 42, col: 0)
    let position = state.position(ofUTF16: offset(of: "세상"))

    XCTAssertEqual(position.line, 42)
    XCTAssertEqual(position.byte, "제조업을 위한 회사. ".utf8.count)
  }

  func testCommandLineAndUnmodifiableBuffersTakeNoEmoji() {
    XCTAssertFalse(NeovimState(mode: "c", lines: lines, line: 1, col: 0).acceptsEmoji)
    XCTAssertFalse(NeovimState(mode: "n", editable: false, lines: lines, line: 1, col: 0).acceptsEmoji)
    XCTAssertTrue(NeovimState(mode: "niI", lines: lines, line: 1, col: 0).acceptsEmoji)
  }

  func testDecodesNeovimsJSON() throws {
    let json = """
      {"mode":"i","blocking":false,"buffer":3,"tick":11,"editable":true,"first":1,"lines":["a"],
       "line":1,"col":1,"vline":1,"vcol":1,"rows":39,"columns":164,"screenRow":2,"screenCol":3,"focused":true}
      """
    let state = try JSONDecoder().decode(NeovimState.self, from: Data(json.utf8))

    XCTAssertEqual(state.focused, true)
    XCTAssertNil(state.seen)
    XCTAssertEqual(state.selectedUTF16, 1..<1)
  }

  private func offset(of needle: String) -> Int {
    let text = lines.joined(separator: "\n")
    return text.utf16.distance(from: text.startIndex, to: text.range(of: needle)!.lowerBound)
  }
}

final class MessagePackTests: XCTestCase {
  func testARequestRoundTrips() throws {
    let long = String(repeating: "가", count: 40)
    let request = MessagePack.array([.int(0), .int(300), .string("nvim_exec_lua"), .array([.string(long), .array([.int(-5), .bool(true), .null])])])
    let decoded = try XCTUnwrap(try MessagePack.decode(request.encoded()))

    XCTAssertEqual(decoded.length, request.encoded().count)
    let parts = try XCTUnwrap(decoded.value.array)
    XCTAssertEqual(parts[1].int, 300)
    XCTAssertEqual(parts[2].string, "nvim_exec_lua")
    let parameters = try XCTUnwrap(parts[3].array)
    XCTAssertEqual(parameters[0].string, long)
    XCTAssertEqual(parameters[1].array?[0].int, -5)
    XCTAssertEqual(parameters[1].array?[1].bool, true)
  }

  func testAPartialMessageWaitsForMoreBytes() throws {
    let bytes = MessagePack.string("hello world").encoded()

    XCTAssertNil(try MessagePack.decode(Array(bytes.dropLast())))
  }

  func testDecodesMapsAndExtensionHandles() throws {
    let bytes: [UInt8] = [0x82, 0xA4, 0x6D, 0x6F, 0x64, 0x65, 0xA1, 0x6E, 0xA3, 0x62, 0x75, 0x66, 0xD4, 0x00, 0x01]
    let value = try XCTUnwrap(try MessagePack.decode(bytes)).value

    XCTAssertEqual(value["mode"]?.string, "n")
    guard case .ext(0, [0x01])? = value["buf"] else { return XCTFail("expected a buffer handle") }
  }
}
