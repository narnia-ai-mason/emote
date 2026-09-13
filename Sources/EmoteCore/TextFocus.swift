import Foundation
import NaturalLanguage

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
  if let range = sentenceUTF16Range(at: location, in: text) {
    return utf16Substring(text, range).trimmingCharacters(in: .whitespacesAndNewlines)
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

private func sentenceUTF16Range(at location: Int, in text: String) -> Range<Int>? {
  let ranges = sentenceUTF16Ranges(in: text)
  if let range = ranges.first(where: { $0.contains(location) }) {
    return range
  }
  return ranges.last(where: { $0.upperBound <= location })
}

private func isAtSentenceStart(cursorUTF16: Int, sentence: String, in text: String) -> Bool {
  guard let range = sentenceUTF16Range(at: cursorUTF16, in: text) else {
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
  guard let probe = characterIndexBeforeCursor(utf16: location, in: text) else {
    return nil
  }

  let tokenizer = NLTokenizer(unit: .word)
  tokenizer.string = text
  if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
    tokenizer.setLanguage(language)
  }

  guard let token = tokenizer.tokens(for: text.startIndex..<text.endIndex).first(where: { $0.contains(probe) })
  else {
    return nil
  }

  let word = String(text[token])
  guard !word.isEmpty else {
    return nil
  }
  return (word, utf16Range(of: token, in: text))
}

private func characterIndexBeforeCursor(utf16 location: Int, in text: String) -> String.Index? {
  guard !text.isEmpty else {
    return nil
  }

  let clamped = min(max(location, 0), text.utf16.count)
  guard let cursor = stringIndex(ofUTF16: clamped, in: text) else {
    return nil
  }

  var index = cursor
  if index == text.startIndex {
    return text[index].isWhitespace ? nil : index
  }

  index = text.index(before: index)
  while text[index].isWhitespace {
    if index == text.startIndex {
      return nil
    }
    index = text.index(before: index)
  }
  return index
}

private func isSentenceTerminator(_ character: Character) -> Bool {
  character == "."
    || character == "!"
    || character == "?"
    || character == "。"
    || character == "…"
    || character == "！"
    || character == "？"
}

private func stringIndex(ofUTF16 offset: Int, in text: String) -> String.Index? {
  let view = text.utf16
  guard let utf16Index = view.index(view.startIndex, offsetBy: offset, limitedBy: view.endIndex) else {
    return nil
  }
  if let index = String.Index(utf16Index, within: text) {
    return index
  }

  var probe = utf16Index
  while probe > view.startIndex {
    probe = view.index(before: probe)
    if let index = String.Index(probe, within: text) {
      return index
    }
  }
  return text.startIndex
}

private func utf16Range(of range: Range<String.Index>, in text: String) -> Range<Int> {
  let view = text.utf16
  let lower = view.distance(from: view.startIndex, to: range.lowerBound)
  let upper = view.distance(from: view.startIndex, to: range.upperBound)
  return lower..<upper
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
