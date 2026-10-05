import Foundation

/// What Emote reads from a Neovim instance: lines around the cursor, the cursor, the mode, and
/// where the cursor sits on the terminal grid. Lines and screen rows count from 1, byte columns from 0.
public struct NeovimState: Codable, Equatable, Sendable {
  public var mode: String
  public var blocking: Bool
  public var buffer: Int
  public var tick: Int
  public var editable: Bool
  /// The buffer line number of `lines[0]`.
  public var first: Int
  public var lines: [String]
  public var line: Int
  public var col: Int
  /// The other end of a Visual selection; the cursor itself outside Visual mode.
  public var vline: Int
  public var vcol: Int
  public var rows: Int
  public var columns: Int
  public var screenRow: Int
  public var screenCol: Int
  /// When the person last moved, typed, or focused this instance, in seconds since 1970.
  public var seen: Double?
  /// The terminal's last focus report, when it sends them.
  public var focused: Bool?

  public init(
    mode: String,
    blocking: Bool = false,
    buffer: Int = 1,
    tick: Int = 1,
    editable: Bool = true,
    first: Int = 1,
    lines: [String],
    line: Int,
    col: Int,
    vline: Int? = nil,
    vcol: Int? = nil,
    rows: Int = 40,
    columns: Int = 120,
    screenRow: Int = 1,
    screenCol: Int = 1,
    seen: Double? = nil,
    focused: Bool? = nil
  ) {
    self.mode = mode
    self.blocking = blocking
    self.buffer = buffer
    self.tick = tick
    self.editable = editable
    self.first = first
    self.lines = lines
    self.line = line
    self.col = col
    self.vline = vline ?? line
    self.vcol = vcol ?? col
    self.rows = rows
    self.columns = columns
    self.screenRow = screenRow
    self.screenCol = screenCol
    self.seen = seen
    self.focused = focused
  }

  public var text: String { lines.joined(separator: "\n") }

  private var kind: Character? { mode.first }

  /// Insert, Replace, Normal, and Visual modes edit the buffer. Command-line, terminal, and
  /// prompts do not, and a blocked instance is waiting on something else.
  public var acceptsEmoji: Bool {
    guard editable, !blocking, let kind else { return false }
    return "iRnvV\u{16}".contains(kind)
  }

  /// The caret in `text`. Insert mode's cursor sits between characters. Normal mode's sits on one:
  /// the end of a word or sentence means after it, anywhere else before it.
  /// Visual mode selects from its other end through the character under the cursor.
  public var selectedUTF16: Range<Int> {
    switch kind {
    case "v", "\u{16}":
      let (start, end) = ordered((vline, vcol), (line, col))
      let lower = utf16(line: start.0, byte: start.1)
      return lower..<max(lower, utf16(line: end.0, byte: end.1 + characterLength(line: end.0, byte: end.1)))
    case "V":
      let (start, end) = ordered((vline, 0), (line, 0))
      let lower = utf16(line: start.0, byte: 0)
      return lower..<max(lower, utf16(line: end.0, byte: Int.max))
    case "i", "R":
      let caret = utf16(line: line, byte: col)
      return caret..<caret
    default:
      let length = characterLength(line: line, byte: col)
      let under = character(line: line, byte: col)
      let endsSomething = under.map { $0.isLetter || $0.isNumber || $0.isPunctuation && $0 != "#" } ?? false
      let after = endsSomething && (character(line: line, byte: col + length)?.isWhitespace ?? true)
      let caret = utf16(line: line, byte: after ? col + length : col)
      return caret..<caret
    }
  }

  public var isVisual: Bool {
    guard let kind else { return false }
    return "vV\u{16}".contains(kind)
  }

  /// A `text` offset as a buffer line and byte column.
  public func position(ofUTF16 offset: Int) -> (line: Int, byte: Int) {
    var remaining = max(offset, 0)
    for (index, content) in lines.enumerated() {
      let length = content.utf16.count
      if remaining <= length {
        let prefix = String(content.utf16.prefix(remaining)) ?? String(content.prefix(remaining))
        return (first + index, prefix.utf8.count)
      }
      remaining -= length + 1
    }
    let last = lines.last ?? ""
    return (first + max(lines.count - 1, 0), last.utf8.count)
  }

  private func content(_ line: Int) -> String? {
    let index = line - first
    return lines.indices.contains(index) ? lines[index] : nil
  }

  private func utf16(line: Int, byte: Int) -> Int {
    let clampedLine = min(max(line, first), first + max(lines.count - 1, 0))
    var offset = 0
    for index in 0..<(clampedLine - first) {
      offset += lines[index].utf16.count + 1
    }
    guard let content = content(clampedLine) else { return offset }
    let bytes = Array(content.utf8)
    let prefix = bytes.prefix(min(max(line == clampedLine ? byte : (line < first ? 0 : Int.max), 0), bytes.count))
    return offset + String(decoding: prefix, as: UTF8.self).utf16.count
  }

  private func character(line: Int, byte: Int) -> Character? {
    guard let content = content(line) else { return nil }
    let bytes = Array(content.utf8)
    guard byte >= 0, byte < bytes.count else { return nil }
    return String(decoding: bytes[byte...], as: UTF8.self).first
  }

  private func characterLength(line: Int, byte: Int) -> Int {
    character(line: line, byte: byte).map { String($0).utf8.count } ?? 0
  }

  private func ordered(_ a: (Int, Int), _ b: (Int, Int)) -> ((Int, Int), (Int, Int)) {
    a.0 < b.0 || (a.0 == b.0 && a.1 <= b.1) ? (a, b) : (b, a)
  }
}
