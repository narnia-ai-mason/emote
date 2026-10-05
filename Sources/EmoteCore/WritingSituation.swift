import Foundation
import NaturalLanguage

public struct WritingSituation: Equatable, Sendable {
  public enum Mode: String, Codable, Equatable, Sendable {
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

  /// `following` is text after the field, as when a block editor keeps the next paragraph in
  /// another field. A heading at the end of `text` takes its next sentence from there.
  public static func resolve(
    text: String,
    selectedUTF16: Range<Int>,
    tone: String?,
    following: String? = nil
  ) -> WritingSituation? {
    let tone = normalizedTone(tone)
    let end = text.utf16.count
    let lower = min(max(selectedUTF16.lowerBound, 0), end)
    let upper = min(max(selectedUTF16.upperBound, lower), end)
    let after = following.map { isHeadingLine($0) ? "" : firstSentence(in: $0) } ?? ""

    let crossesLines = upper > lower && substring(text, lower..<upper).contains("\n")
    if !crossesLines, let marked = markupHeading(at: lower, in: text) {
      return makeHeading(marked.title, next: marked.next.isEmpty ? after : marked.next, tone: tone)
    }

    if upper > lower {
      let selected = substring(text, lower..<upper)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !selected.isEmpty else {
        return resolve(text: text, selectedUTF16: lower..<lower, tone: tone, following: following)
      }
      if isSentenceShaped(selected) {
        return sentence(selected, tone: tone)
      }
      return word(selected, context: sentenceContaining(utf16: lower, in: text), tone: tone)
    }

    let rewound = rewindClosers(from: lower, in: text)
    if rewound < lower,
      let previous = characterBefore(utf16: rewound, in: text),
      isSentenceFinal(previous)
    {
      let spoken = stripOpeningMarkup(sentenceBefore(caretUTF16: rewound, in: text))
      if !spoken.isEmpty {
        return sentence(spoken, tone: tone)
      }
    }

    if isAtSentenceStart(caret: lower, in: text) {
      let forward = sentenceStarting(at: lower, in: text)
      if hasWords(forward) {
        if endsWithSentenceFinal(forward) {
          return sentence(forward, tone: tone)
        }
        if setextUnderlineLevel(forward) == nil {
          return heading(at: lower, in: text, following: after, tone: tone)
        }
      }
    }

    guard let previous = characterBefore(utf16: lower, in: text) else {
      return nil
    }
    if previous.isWhitespace || isSeparator(previous) {
      let spoken = stripOpeningMarkup(sentenceBefore(caretUTF16: lower, in: text))
      guard !spoken.isEmpty else { return nil }
      return sentence(spoken, tone: tone)
    }

    guard let token = wordTouching(utf16: lower, in: text) else { return nil }
    return word(token, context: sentenceContaining(utf16: lower, in: text), tone: tone)
  }

  private static func heading(
    at caret: Int,
    in text: String,
    following: String,
    tone: String
  ) -> WritingSituation? {
    let next = nextLineFirstSentence(after: caret, in: text)
    return makeHeading(
      sentenceStarting(at: caret, in: text),
      next: next.isEmpty ? following : next,
      tone: tone
    )
  }

  private static func makeHeading(_ title: String, next: String, tone: String) -> WritingSituation? {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let next = next.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty || !next.isEmpty else { return nil }
    let message = """
      <heading>\(title)</heading>
      <next-sentence>\(next)</next-sentence>
      <tone>\(tone)</tone>
      """
    return WritingSituation(
      mode: .heading,
      instructions: headingInstructions,
      message: message,
      span: title,
      tokens: tokens(in: title),
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

  /// Quotes and emphasis sitting after a finished sentence are not the start of a new heading.
  private static func rewindClosers(from caret: Int, in text: String) -> Int {
    var index = caret
    while index > 0, let character = characterBefore(utf16: index, in: text) {
      if character == "\n" || !isClosingMark(character) { break }
      index -= character.utf16.count
    }
    return index
  }

  private static func isClosingMark(_ character: Character) -> Bool {
    "\"'*_`“”‘’".contains(character)
  }

  private static func stripOpeningMarkup(_ text: String) -> String {
    var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix(">") {
      line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    for prefix in ["*\"", "\"", "*", "“"] where line.hasPrefix(prefix) {
      line.removeFirst(prefix.count)
      break
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isSentenceFinal(_ character: Character) -> Bool {
    ".!?。！？…".contains(character)
  }

  private static func endsWithSentenceFinal(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
    return isSentenceFinal(last)
  }

  /// The caret sits at a sentence boundary: the document start, a new line, or past the space after a
  /// sentence-final mark. Touching the mark, it ends that sentence instead.
  private static func isAtSentenceStart(caret: Int, in text: String) -> Bool {
    var index = caret
    var spaced = false
    while index > 0 {
      guard let character = characterBefore(utf16: index, in: text) else { return true }
      if character == "\n" { return true }
      if character.isWhitespace {
        index -= character.utf16.count
        spaced = true
        continue
      }
      return spaced && isSentenceFinal(character)
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

  /// Markdown puts a blank line between a heading and its paragraph, so blank lines are skipped.
  /// A heading that follows directly says nothing about this one.
  private static func nextLineFirstSentence(after caret: Int, in text: String) -> String {
    var line = textLine(at: caret, in: text)
    while let following = textLineAfter(line, in: text) {
      if !following.content.trimmingCharacters(in: .whitespaces).isEmpty {
        return isHeadingLine(following.content) ? "" : firstSentence(in: following.content)
      }
      line = following
    }
    return ""
  }

  private static func isHeadingLine(_ line: String) -> Bool {
    prefixHeadingTitle(line, marker: "#", maxCount: 6, allowEmpty: true) != nil
      || prefixHeadingTitle(line, marker: "=", maxCount: 6, allowEmpty: false) != nil
      || htmlHeadingTitle(line) != nil
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
    let last = lastSentence(in: trimmed)
    // An emoji or closing quote after a sentence's period belongs to that sentence.
    guard !hasWords(last), trimmed.hasSuffix(last) else { return last }
    let rest = String(trimmed.dropLast(last.count))
    guard !rest.hasSuffix("\n") else { return last }
    let earlier = lastSentence(in: rest.trimmingCharacters(in: .whitespaces))
    return earlier.isEmpty ? last : earlier + " " + last
  }

  private static func hasWords(_ text: String) -> Bool {
    text.contains { $0.isLetter || $0.isNumber }
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

  /// A markup heading on the caret's line: Markdown `#` / setext underlines, AsciiDoc `=`, or an HTML `<h1>`–`<h6>`.
  private static func markupHeading(at caret: Int, in text: String) -> (title: String, next: String)? {
    let current = textLine(at: caret, in: text)
    if let title = prefixHeadingTitle(current.content, marker: "#", maxCount: 6, allowEmpty: true) {
      return (title, sentenceAfter(current, in: text, skipUnderline: true))
    }
    if let title = prefixHeadingTitle(current.content, marker: "=", maxCount: 6, allowEmpty: false) {
      return (title, sentenceAfter(current, in: text, skipUnderline: true))
    }
    if let title = htmlHeadingTitle(current.content) {
      return (title, sentenceAfter(current, in: text, skipUnderline: true))
    }
    if setextUnderlineLevel(current.content) != nil,
      let previous = textLineBefore(current, in: text),
      let title = setextTitle(previous.content)
    {
      return (title, sentenceAfter(current, in: text, skipUnderline: false))
    }
    if let following = textLineAfter(current, in: text),
      setextUnderlineLevel(following.content) != nil,
      let title = setextTitle(current.content)
    {
      return (title, sentenceAfter(current, in: text, skipUnderline: true))
    }
    return nil
  }

  /// An opening run of `marker` (1...maxCount) after at most three spaces, then a space and a title.
  /// A closing run of the same marker is removed when a space precedes it.
  private static func prefixHeadingTitle(
    _ line: String,
    marker: Character,
    maxCount: Int,
    allowEmpty: Bool
  ) -> String? {
    var index = line.startIndex
    var indent = 0
    while index < line.endIndex, line[index] == " ", indent < 4 {
      indent += 1
      index = line.index(after: index)
    }
    if indent > 3 { return nil }

    var count = 0
    while index < line.endIndex, line[index] == marker {
      count += 1
      if count > maxCount { return nil }
      index = line.index(after: index)
    }
    guard (1...maxCount).contains(count) else { return nil }

    if index == line.endIndex {
      return allowEmpty ? "" : nil
    }
    let separator = line[index]
    guard separator == " " || separator == "\t" else { return nil }

    var title = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
    let trailing = title.reversed().prefix(while: { $0 == marker }).count
    if trailing > 0 {
      let cut = title.index(title.endIndex, offsetBy: -trailing)
      let stem = title[..<cut]
      if stem.isEmpty || stem.last?.isWhitespace == true {
        title = stem.trimmingCharacters(in: .whitespaces)
      }
    }
    if title.isEmpty, !allowEmpty { return nil }
    return title
  }

  private static func htmlHeadingTitle(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 4 else { return nil }
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("<h") else { return nil }
    let levelIndex = lower.index(lower.startIndex, offsetBy: 2)
    guard let level = lower[levelIndex].wholeNumberValue, (1...6).contains(level) else { return nil }
    let afterLevel = lower.index(after: levelIndex)
    if afterLevel < lower.endIndex {
      let marker = lower[afterLevel]
      guard marker == ">" || marker == " " || marker == "\t" || marker == "/" else { return nil }
    }
    guard let openEnd = trimmed.firstIndex(of: ">") else { return nil }
    let rest = trimmed[trimmed.index(after: openEnd)...]
    let closing = "</h\(level)>"
    if let closeRange = rest.range(of: closing, options: [.caseInsensitive, .backwards]) {
      let tail = rest[closeRange.upperBound...].trimmingCharacters(in: .whitespaces)
      guard tail.isEmpty else { return nil }
      return rest[..<closeRange.lowerBound].trimmingCharacters(in: .whitespaces)
    }
    let title = rest.trimmingCharacters(in: .whitespaces)
    guard !title.contains("<") else { return nil }
    return title
  }

  private static func setextTitle(_ line: String) -> String? {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    if leadingSpaces > 3 { return nil }
    let title = line.trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty, setextUnderlineLevel(title) == nil else { return nil }
    return title
  }

  /// A Markdown setext underline: three or more `=` or `-`, indented by at most three spaces.
  private static func setextUnderlineLevel(_ line: String) -> Int? {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    if leadingSpaces > 3 { return nil }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 3 else { return nil }
    if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
    if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
    return nil
  }

  private struct TextLine {
    var content: String
    var bounds: Range<Int>
  }

  private static func textLine(at caret: Int, in text: String) -> TextLine {
    let bounds = lineUTF16Bounds(at: caret, in: text)
    var content = substring(text, bounds)
    if content.hasSuffix("\r") { content.removeLast() }
    return TextLine(content: content, bounds: bounds)
  }

  private static func textLineAfter(_ line: TextLine, in text: String) -> TextLine? {
    let count = text.utf16.count
    guard line.bounds.upperBound < count else { return nil }
    let start = line.bounds.upperBound + 1
    if start > count { return nil }
    if start == count { return TextLine(content: "", bounds: start..<start) }
    return textLine(at: start, in: text)
  }

  private static func textLineBefore(_ line: TextLine, in text: String) -> TextLine? {
    guard line.bounds.lowerBound > 0 else { return nil }
    return textLine(at: line.bounds.lowerBound - 1, in: text)
  }

  private static func sentenceAfter(_ line: TextLine, in text: String, skipUnderline: Bool) -> String {
    guard var following = textLineAfter(line, in: text) else { return "" }
    if skipUnderline, setextUnderlineLevel(following.content) != nil {
      guard let afterUnderline = textLineAfter(following, in: text) else { return "" }
      following = afterUnderline
    }
    if following.content.trimmingCharacters(in: .whitespaces).isEmpty {
      return nextLineFirstSentence(after: following.bounds.lowerBound, in: text)
    }
    return isHeadingLine(following.content) ? "" : firstSentence(in: following.content)
  }

  private static func lineUTF16Bounds(at caret: Int, in text: String) -> Range<Int> {
    let newline = "\n".utf16.first ?? 10
    let view = text.utf16
    let clamped = min(max(caret, 0), view.count)
    var offset = 0
    var lineStart = 0
    var index = view.startIndex
    while index < view.endIndex, offset < clamped {
      if view[index] == newline {
        lineStart = offset + 1
      }
      index = view.index(after: index)
      offset += 1
    }
    var lineEnd = offset
    while index < view.endIndex, view[index] != newline {
      index = view.index(after: index)
      lineEnd += 1
    }
    return lineStart..<lineEnd
  }
}
