import Foundation

public enum EmojiCatalog {
  public static func name(for emoji: String) -> String? {
    catalog.names[emoji] ?? catalog.namesByNormalized[normalized(emoji)]
  }

  public static var all: [EmojiRecommendation] {
    catalog.recommendations
  }

  public static func recommendation(matching raw: String) -> EmojiRecommendation? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    if let name = catalog.names[trimmed] {
      return EmojiRecommendation(emoji: trimmed, description: name)
    }

    let key = normalized(stripSkinTone(trimmed))
    guard let emoji = catalog.emojiByNormalized[key], let name = catalog.names[emoji] else {
      return nil
    }
    return EmojiRecommendation(emoji: emoji, description: name)
  }

  private static let catalog: Catalog = {
    let url = ResourceFile.url(name: "emoji-test-17.0", extension: "txt")!
    let contents = try! String(contentsOf: url, encoding: .utf8)
    var names: [String: String] = [:]
    var recommendations: [EmojiRecommendation] = []
    var namesByNormalized: [String: String] = [:]
    var emojiByNormalized: [String: String] = [:]

    for line in contents.split(separator: "\n") {
      guard
        line.contains("; fully-qualified"),
        let commentStart = line.range(of: "# ")?.upperBound
      else {
        continue
      }

      let fields = line[commentStart...].split(
        separator: " ",
        maxSplits: 2
      )
      guard fields.count == 3 else {
        continue
      }

      let emoji = String(fields[0])
      guard !emoji.unicodeScalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }) else {
        continue
      }
      let name = fields[2]
      let description = name.prefix(1).uppercased() + name.dropFirst()
      names[emoji] = description
      namesByNormalized[normalized(emoji)] = description
      emojiByNormalized[normalized(emoji)] = emoji
      recommendations.append(
        EmojiRecommendation(emoji: emoji, description: description)
      )
    }

    return Catalog(
      names: names,
      recommendations: recommendations,
      namesByNormalized: namesByNormalized,
      emojiByNormalized: emojiByNormalized
    )
  }()

  static func normalized(_ emoji: String) -> String {
    String(
      emoji.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }
    )
  }

  static func stripSkinTone(_ emoji: String) -> String {
    String(
      emoji.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) }
    )
  }

  private struct Catalog {
    let names: [String: String]
    let recommendations: [EmojiRecommendation]
    let namesByNormalized: [String: String]
    let emojiByNormalized: [String: String]
  }
}
