import Foundation

public struct CldrKeywordIndex: Sendable {
  private let emojiForKeyword: [String: [String]]

  public init(tsv: String) {
    var index: [String: [String]] = [:]
    for line in tsv.split(separator: "\n") {
      if line.hasPrefix("#") { continue }
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count >= 5 else { continue }
      let emoji = String(fields[0])
      let labels = [String(fields[1]), String(fields[3])] + keywordList(fields[2]) + keywordList(fields[4])
      for label in labels {
        let key = Self.normalize(label)
        guard key.count >= 1 else { continue }
        var matches = index[key] ?? []
        if !matches.contains(emoji) {
          matches.append(emoji)
        }
        index[key] = matches
      }
    }
    emojiForKeyword = index
  }

  public static func loadBundled() -> CldrKeywordIndex {
    guard
      let url = ResourceFile.url(name: "emoji-cldr-48.2", extension: "tsv"),
      let tsv = try? String(contentsOf: url, encoding: .utf8)
    else {
      return CldrKeywordIndex(tsv: "")
    }
    return CldrKeywordIndex(tsv: tsv)
  }

  /// Every token has to hit. One token returns its emoji list. A short phrase
  /// returns the union only when each token is in CLDR.
  public func match(tokens: [String], limit: Int = 10) -> [String]? {
    let keys = tokens.map(Self.normalize).filter { !$0.isEmpty }
    guard !keys.isEmpty else { return nil }
    var union: [String] = []
    for key in keys {
      guard let hits = emojiForKeyword[key], !hits.isEmpty else { return nil }
      for emoji in hits where !union.contains(emoji) {
        union.append(emoji)
        if union.count == limit { return union }
      }
    }
    return union.isEmpty ? nil : union
  }

  private static func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

private func keywordList(_ field: Substring) -> [String] {
  field.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
}
