import Foundation
import NaturalLanguage

public struct WritingSituation: Equatable, Sendable {
  public enum Mode: String, Equatable, Sendable {
    case heading
    case sentence
    case word
  }

  public var mode: Mode
  public var instructions: String
  public var message: String
  public var span: String
  public var tokens: [String]
  public var tone: String

  public static let headingInstructions = """
    You recommend emojis a person would place before a section heading. Pick a representative mark for the section's topic, not the emotion of the following sentence. If the next sentence is empty, use only the heading. Match the requested tone. Reply as JSON with key emojis: 5 to 10 distinct emoji characters.
    """

  public static let sentenceInstructions = """
    You recommend emojis a person would place after a sentence while writing. Prefer the writer's intent over a literal picture of one word. Match the requested tone. Reply as JSON with key emojis: 5 to 10 distinct emoji characters.
    """

  public static let wordInstructions = """
    You recommend emojis a person would place next to a short span while writing. Prefer the sense of that span over a picture of one unrelated noun. Match the requested tone. Reply as JSON with key emojis: 5 to 10 distinct emoji characters.
    """

  public static func resolve(
    text: String,
    selectedUTF16: Range<Int>,
    tone: String?
  ) -> WritingSituation? {
    let tone = normalizedTone(tone)
    let end = text.utf16.count
    let lower = min(max(selectedUTF16.lowerBound, 0), end)
    let upper = min(max(selectedUTF16.upperBound, lower), end)

    if upper > lower {
      let selected = substring(text, lower..<upper)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !selected.isEmpty else {
        return resolve(text: text, selectedUTF16: lower..<lower, tone: tone)
      }
      if isSentenceShaped(selected) {
        return sentence(selected, tone: tone)
      }
      return word(selected, context: sentenceContaining(utf16: lower, in: text), tone: tone)
    }

    if isAtSentenceStart(caret: lower, in: text) {
      let forward = sentenceStarting(at: lower, in: text)
      if !forward.isEmpty {
        if endsWithSentenceFinal(forward) {
          return sentence(forward, tone: tone)
        }
        return heading(at: lower, in: text, tone: tone)
      }
    }

    guard let previous = characterBefore(utf16: lower, in: text) else {
      return nil
    }
    if previous.isWhitespace || isSeparator(previous) {
      let spoken = sentenceBefore(caretUTF16: lower, in: text)
      guard !spoken.isEmpty else { return nil }
      return sentence(spoken, tone: tone)
    }

    guard let token = wordTouching(utf16: lower, in: text) else { return nil }
    return word(token, context: sentenceContaining(utf16: lower, in: text), tone: tone)
  }

  private static func heading(at caret: Int, in text: String, tone: String) -> WritingSituation? {
    let heading = sentenceStarting(at: caret, in: text)
    let next = nextLineFirstSentence(after: caret, in: text)
    guard !heading.isEmpty else { return nil }
    let message = """
      <heading>\(heading)</heading>
      <next-sentence>\(next)</next-sentence>
      <tone>\(tone)</tone>
      """
    return WritingSituation(
      mode: .heading,
      instructions: headingInstructions,
      message: message,
      span: heading,
      tokens: tokens(in: heading),
      tone: tone
    )
  }

  private static func sentence(_ spoken: String, tone: String) -> WritingSituation {
    let message = """
      <sentence>\(spoken)</sentence>
      <tone>\(tone)</tone>
      """
    return WritingSituation(
      mode: .sentence,
      instructions: sentenceInstructions,
      message: message,
      span: spoken,
      tokens: tokens(in: spoken),
      tone: tone
    )
  }

  private static func word(_ span: String, context: String, tone: String) -> WritingSituation {
    var lines = ["<word>\(span)</word>"]
    let context = context.trimmingCharacters(in: .whitespacesAndNewlines)
    if !context.isEmpty, context != span {
      lines.append("<sentence>\(context)</sentence>")
    }
    lines.append("<tone>\(tone)</tone>")
    return WritingSituation(
      mode: .word,
      instructions: wordInstructions,
      message: lines.joined(separator: "\n"),
      span: span,
      tokens: tokens(in: span),
      tone: tone
    )
  }

  private static func normalizedTone(_ tone: String?) -> String {
    SuggestionTone.resolve(tone).rawValue
  }

  static func isSentenceShaped(_ text: String) -> Bool {
    if text.contains(where: isSeparator) { return true }
    if text.count > 30 { return true }
    return tokens(in: text).count >= 6
  }

  static func tokens(in text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
      tokenizer.setLanguage(language)
    }
    return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
  }

  private static func isSeparator(_ character: Character) -> Bool {
    ".,;!?。，；！？".contains(character)
  }

  private static func isSentenceFinal(_ character: Character) -> Bool {
    ".!?。！？…".contains(character)
  }

  private static func endsWithSentenceFinal(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
    return isSentenceFinal(last)
  }

  /// The caret sits at a sentence boundary: the document start, a new line, or just after a sentence-final mark.
  private static func isAtSentenceStart(caret: Int, in text: String) -> Bool {
    var index = caret
    while index > 0 {
      guard let character = characterBefore(utf16: index, in: text) else { return true }
      if character == "\n" { return true }
      if character.isWhitespace {
        index -= character.utf16.count
        continue
      }
      return isSentenceFinal(character)
    }
    return true
  }

  /// The sentence that begins at the caret, stopping at the first sentence-final mark or the end of the line.
  private static func sentenceStarting(at caret: Int, in text: String) -> String {
    guard var index = stringIndex(ofUTF16: caret, in: text) else { return "" }
    while index < text.endIndex {
      let character = text[index]
      if character == "\n" { return "" }
      if !character.isWhitespace { break }
      index = text.index(after: index)
    }
    var result = ""
    while index < text.endIndex {
      let character = text[index]
      if character == "\n" { break }
      result.append(character)
      index = text.index(after: index)
      if isSentenceFinal(character) { break }
    }
    return result.trimmingCharacters(in: .whitespaces)
  }

  private static func nextLineFirstSentence(after caret: Int, in text: String) -> String {
    guard var index = stringIndex(ofUTF16: caret, in: text) else { return "" }
    while index < text.endIndex, text[index] != "\n" {
      index = text.index(after: index)
    }
    guard index < text.endIndex else { return "" }
    index = text.index(after: index)
    var line = ""
    while index < text.endIndex, text[index] != "\n" {
      line.append(text[index])
      index = text.index(after: index)
    }
    return firstSentence(in: line)
  }

  private static func firstSentence(in line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return "" }
    var result = ""
    for character in trimmed {
      result.append(character)
      if isSeparator(character), character != ",", character != ";", character != "，", character != "；" {
        break
      }
    }
    return result.trimmingCharacters(in: .whitespaces)
  }

  private static func sentenceBefore(caretUTF16: Int, in text: String) -> String {
    let prefix = substring(text, 0..<caretUTF16)
    let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return lastSentence(in: trimmed)
  }

  private static func lastSentence(in text: String) -> String {
    var start = text.startIndex
    var pending = false
    var latest = text.startIndex..<text.endIndex
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let next = text.index(after: index)
      if character == "\n" {
        if index > start { latest = start..<index }
        start = next
        pending = false
      } else if isSeparator(character) {
        pending = true
        latest = start..<next
      } else if pending {
        latest = start..<index
        start = index
        pending = false
        if character.isWhitespace { start = next }
      }
      index = next
    }
    if !pending, start < text.endIndex {
      latest = start..<text.endIndex
    }
    return String(text[latest]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func sentenceContaining(utf16 location: Int, in text: String) -> String {
    let clamped = min(max(location, 0), text.utf16.count)
    let through = substring(text, 0..<clamped)
    let linePrefix: String
    if let newline = through.lastIndex(of: "\n") {
      linePrefix = String(through[through.index(after: newline)...])
    } else {
      linePrefix = through
    }
    var rest = ""
    if let index = stringIndex(ofUTF16: clamped, in: text) {
      var cursor = index
      while cursor < text.endIndex, text[cursor] != "\n" {
        rest.append(text[cursor])
        let character = text[cursor]
        cursor = text.index(after: cursor)
        if isSeparator(character), character != ",", character != ";", character != "，", character != "；" {
          break
        }
      }
    }
    return lastSentence(in: (linePrefix + rest).trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func wordTouching(utf16 caret: Int, in text: String) -> String? {
    guard let probe = stringIndex(ofUTF16: max(caret - 1, 0), in: text) else { return nil }
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
      tokenizer.setLanguage(language)
    }
    guard let token = tokenizer.tokens(for: text.startIndex..<text.endIndex).first(where: { $0.contains(probe) })
    else { return nil }
    let word = String(text[token]).trimmingCharacters(in: .whitespacesAndNewlines)
    return word.isEmpty ? nil : word
  }

  private static func characterBefore(utf16 caret: Int, in text: String) -> Character? {
    guard caret > 0 else { return nil }
    return substring(text, (caret - 1)..<caret).first
  }

  private static func substring(_ text: String, _ range: Range<Int>) -> String {
    let view = text.utf16
    guard
      let start = view.index(view.startIndex, offsetBy: range.lowerBound, limitedBy: view.endIndex),
      let end = view.index(view.startIndex, offsetBy: range.upperBound, limitedBy: view.endIndex),
      let string = String(view[start..<end])
    else { return "" }
    return string
  }

  private static func stringIndex(ofUTF16 offset: Int, in text: String) -> String.Index? {
    let view = text.utf16
    guard let utf16Index = view.index(view.startIndex, offsetBy: offset, limitedBy: view.endIndex) else {
      return nil
    }
    if let index = String.Index(utf16Index, within: text) { return index }
    var probe = utf16Index
    while probe > view.startIndex {
      probe = view.index(before: probe)
      if let index = String.Index(probe, within: text) { return index }
    }
    return text.startIndex
  }
}
