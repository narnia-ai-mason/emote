import Foundation

enum EmojiResponseParser {
  static func recommendations(from content: String, limit: Int) -> [EmojiRecommendation] {
    var seen = Set<String>()
    var results: [EmojiRecommendation] = []

    for raw in rawCandidates(in: content) {
      guard let recommendation = EmojiCatalog.recommendation(matching: raw) else {
        continue
      }
      guard seen.insert(recommendation.emoji).inserted else {
        continue
      }
      results.append(recommendation)
      if results.count == limit {
        return results
      }
    }

    return results
  }

  static func rawCandidates(in content: String) -> [String] {
    if let fromJSON = jsonCandidates(in: content), !fromJSON.isEmpty {
      return fromJSON
    }
    return catalogMatches(in: content)
  }

  private static func jsonCandidates(in content: String) -> [String]? {
    guard let payload = jsonObject(in: content) else {
      return nil
    }

    if let emojis = payload["emojis"] as? [String] {
      return emojis
    }
    if let recommendations = payload["recommendations"] as? [[String: Any]] {
      return recommendations.compactMap { item in
        item["emoji"] as? String
      }
    }
    return nil
  }

  private static func jsonObject(in content: String) -> [String: Any]? {
    let trimmed = stripFences(content)
    if let parsed = decodeObject(trimmed) {
      return parsed
    }

    guard
      let start = trimmed.firstIndex(of: "{"),
      let end = trimmed.lastIndex(of: "}"),
      start < end
    else {
      return nil
    }

    let slice = String(trimmed[start...end])
    return decodeObject(slice)
  }

  private static func decodeObject(_ text: String) -> [String: Any]? {
    guard
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return nil
    }
    return dictionary
  }

  private static func stripFences(_ content: String) -> String {
    var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
      if let newline = text.firstIndex(of: "\n") {
        text = String(text[text.index(after: newline)...])
      }
      if let fence = text.range(of: "```", options: .backwards) {
        text = String(text[..<fence.lowerBound])
      }
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func catalogMatches(in content: String) -> [String] {
    var matches: [(String.Index, String)] = []
    for recommendation in EmojiCatalog.all {
      var searchStart = content.startIndex
      while let range = content.range(
        of: recommendation.emoji,
        range: searchStart..<content.endIndex
      ) {
        matches.append((range.lowerBound, recommendation.emoji))
        searchStart = range.upperBound
      }
    }
    matches.sort { $0.0 < $1.0 }
    return matches.map(\.1)
  }
}
