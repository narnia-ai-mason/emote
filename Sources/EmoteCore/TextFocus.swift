import Foundation

public struct TextFocus: Equatable, Sendable {
  public var kind: EmojiFocusKind
  public var focus: String
  public var sentence: String
  public var insertion: Insertion
  public var anchorUTF16: Range<Int>

  public enum Insertion: Equatable, Sendable {
    case insert(utf16: Int)
    case replace(utf16: Range<Int>)
  }

  public var query: RetrievalQuery {
    RetrievalQuery(
      focus: focus,
      context: kind == .word ? sentence : nil,
      kind: kind
    )
  }

  public static func resolve(text: String, selectedUTF16: Range<Int>) -> TextFocus? {
    let end = text.utf16.count
    let lower = min(max(selectedUTF16.lowerBound, 0), end)
    let upper = min(max(selectedUTF16.upperBound, lower), end)

    if upper > lower {
      let selected = utf16Substring(text, lower..<upper)
      let focus = selected.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !focus.isEmpty else {
        return resolve(text: text, selectedUTF16: lower..<lower)
      }
      let sentence = sentenceContaining(utf16: lower, in: text)
      return TextFocus(
        kind: .word,
        focus: focus,
        sentence: sentence,
        insertion: .replace(utf16: lower..<upper),
        anchorUTF16: lower..<upper
      )
    }

    let sentence = sentenceContaining(utf16: lower, in: text)
    if isAtSentenceStart(cursorUTF16: lower, sentence: sentence, in: text) {
      let focus = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !focus.isEmpty else {
        return nil
      }
      return TextFocus(
        kind: .sentence,
        focus: focus,
        sentence: focus,
        insertion: .insert(utf16: lower),
        anchorUTF16: caretAnchor(at: lower, end: end)
      )
    }

    guard let word = wordAround(utf16: lower, in: text) else {
      let focus = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !focus.isEmpty else {
        return nil
      }
      return TextFocus(
        kind: .sentence,
        focus: focus,
        sentence: focus,
        insertion: .insert(utf16: lower),
        anchorUTF16: caretAnchor(at: lower, end: end)
      )
    }

    return TextFocus(
      kind: .word,
      focus: word.word,
      sentence: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
      insertion: .insert(utf16: lower),
      anchorUTF16: word.range
    )
  }
}

private func sentenceContaining(utf16 location: Int, in text: String) -> String {
  let ranges = sentenceUTF16Ranges(in: text)
  if let range = ranges.first(where: { $0.contains(location) || $0.upperBound == location }) {
    return utf16Substring(text, range).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  if let last = ranges.last, location >= last.upperBound {
    return utf16Substring(text, last).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sentenceUTF16Ranges(in text: String) -> [Range<Int>] {
  var ranges: [Range<Int>] = []
  var start = 0
  var offset = 0
  var pendingTerminator = false

  for character in text {
    let length = character.utf16.count
    if character == "\n" {
      if offset > start {
        ranges.append(start..<offset)
      }
      start = offset + length
      pendingTerminator = false
    } else if isSentenceTerminator(character) {
      pendingTerminator = true
    } else if pendingTerminator {
      ranges.append(start..<offset)
      start = offset
      pendingTerminator = false
      if character.isWhitespace {
        start = offset + length
      }
    }
    offset += length
  }

  if pendingTerminator || offset > start {
    ranges.append(start..<offset)
  }
  return ranges.filter { !$0.isEmpty }
}

private func isAtSentenceStart(cursorUTF16: Int, sentence: String, in text: String) -> Bool {
  guard let range = sentenceUTF16Ranges(in: text).first(where: {
    $0.contains(cursorUTF16) || $0.upperBound == cursorUTF16
  }) else {
    return cursorUTF16 == 0
  }

  let prefix = utf16Substring(text, range.lowerBound..<cursorUTF16)
  return prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func caretAnchor(at location: Int, end: Int) -> Range<Int> {
  if location < end {
    return location..<(location + 1)
  }
  if location > 0 {
    return (location - 1)..<location
  }
  return location..<location
}

private func wordAround(utf16 location: Int, in text: String) -> (word: String, range: Range<Int>)? {
  let scalars = Array(text.utf16)
  guard !scalars.isEmpty else {
    return nil
  }

  var index = min(max(location, 0), scalars.count)
  if index > 0 {
    index -= 1
  }

  while index > 0, isWhitespaceUTF16(scalars[index]) {
    index -= 1
  }

  guard index >= 0, index < scalars.count, isWordUTF16(scalars[index]) else {
    return nil
  }

  var lower = index
  var upper = index + 1
  while lower > 0, isWordUTF16(scalars[lower - 1]) {
    lower -= 1
  }
  while upper < scalars.count, isWordUTF16(scalars[upper]) {
    upper += 1
  }
  return (utf16Substring(text, lower..<upper), lower..<upper)
}

private func isSentenceTerminator(_ character: Character) -> Bool {
  character == "." || character == "!" || character == "?" || character == "。" || character == "…"
}

private func isWordUTF16(_ unit: UInt16) -> Bool {
  let scalar = UnicodeScalar(unit)
  if let scalar {
    let character = Character(scalar)
    return character.isLetter || character.isNumber
  }
  return true
}

private func isWhitespaceUTF16(_ unit: UInt16) -> Bool {
  guard let scalar = UnicodeScalar(unit) else {
    return false
  }
  return CharacterSet.whitespacesAndNewlines.contains(scalar)
}

private func utf16Substring(_ text: String, _ range: Range<Int>) -> String {
  let view = text.utf16
  guard
    let start = view.index(view.startIndex, offsetBy: range.lowerBound, limitedBy: view.endIndex),
    let end = view.index(view.startIndex, offsetBy: range.upperBound, limitedBy: view.endIndex)
  else {
    return ""
  }
  return String(view[start..<end]) ?? ""
}
