public enum EmojiRecommendationPrompt {
  public static let instructions = """
    You recommend emojis that a person would insert while writing.
    Prefer communicative intent over literal translation.
    When a tone and style is provided, every emoji must fit that tone.
    Do not think out loud. Do not include skin-tone variants. Do not repeat emojis.
    """

  public static let jsonInstructions = """
    \(instructions)
    Reply with JSON only.
    """

  public static func userPrompt(
    query: RetrievalQuery,
    count: Int,
    extraInstruction: String? = nil,
    asksForJSON: Bool
  ) -> String {
    var lines: [String] = []
    switch query.kind {
    case .sentence:
      lines.append("Recommend emojis that best fit this entire sentence.")
      lines.append("Sentence: \(query.focus)")
    case .word:
      lines.append("Recommend emojis that best fit this word in its sentence.")
      lines.append("Word: \(query.focus)")
      if let context = query.context, !context.isEmpty {
        lines.append("Sentence: \(context)")
      }
    }
    if let tone = query.tone, !tone.isEmpty {
      lines.append("Tone and style: \(tone)")
    }
    lines.append(
      asksForJSON
        ? "Suggest \(count) distinct, commonly used emojis. No duplicates."
        : "Suggest \(count) distinct emoji characters from different categories. Never repeat a character."
    )
    if let extraInstruction, !extraInstruction.isEmpty {
      lines.append(extraInstruction)
    }
    if asksForJSON {
      lines.append(
        "Return JSON only in this shape: {\"emojis\":[\"<emoji>\",\"<emoji>\",\"<emoji>\"]}"
      )
    }
    return lines.joined(separator: "\n")
  }

  public static func retryInstruction(missing: Int) -> String {
    "The previous answer did not contain enough real Unicode emojis. Suggest \(missing) additional distinct emojis."
  }
}
