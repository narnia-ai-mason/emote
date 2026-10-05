import Foundation

/// VS Code's focused field is one line tall, but its text is a page around the cursor.
/// The reported caret is often only the column on the visible line, not an index into that page.
public enum CaretReconciler: Sendable {
  public static let maxHostHeight: CGFloat = 64

  /// The text from the start of the field up to the caret. It is only the caret when it is a prefix of the field.
  public static func caretOffset(prefix: String, in text: String) -> Int? {
    guard text.hasPrefix(prefix) else { return nil }
    let offset = prefix.utf16.count
    guard offset <= text.utf16.count else { return nil }
    return offset
  }

  /// `column` is the caret as reported by a one-line editor host. A value that fits in the line is a
  /// column counted from the line start. A larger value that already lands in the line is an absolute index.
  public static func caretOffset(column: Int, on line: Range<Int>, textLength: Int) -> Int? {
    guard line.lowerBound >= 0, line.upperBound <= textLength, line.lowerBound <= line.upperBound else {
      return nil
    }
    if column >= 0, column <= line.count {
      return line.lowerBound + column
    }
    if column >= line.lowerBound, column <= line.upperBound {
      return column
    }
    return nil
  }

  /// Chromium answers bounds queries it can't serve with an empty rectangle, sometimes far off the field.
  /// A caret rectangle is believable when it has height and touches the field it belongs to.
  /// Both rectangles are in Accessibility's top-left-origin coordinates.
  public static func isPlausibleCaret(_ rect: CGRect, in field: CGRect?, maxHeight: CGFloat = 200) -> Bool {
    guard !rect.isNull, rect.height > 0, rect.height <= maxHeight else { return false }
    guard let field else { return true }
    return rect.insetBy(dx: -32, dy: -32).intersects(field)
  }

  public static func lineRanges(in text: String) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    var lineStart = 0
    var offset = 0
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let length = character.utf16.count
      if character == "\n" {
        var end = offset
        if end > lineStart {
          let unit = text.utf16[text.utf16.index(text.utf16.startIndex, offsetBy: end - 1)]
          if unit == 13 { end -= 1 }
        }
        ranges.append(lineStart..<end)
        lineStart = offset + length
      }
      offset += length
      index = text.index(after: index)
    }
    ranges.append(lineStart..<offset)
    return ranges
  }
}
