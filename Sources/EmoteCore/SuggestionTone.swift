import Foundation

public enum SuggestionTone: String, CaseIterable, Sendable {
  case neutral
  case dry
  case warm
  case playful

  public static func resolve(_ raw: String?) -> SuggestionTone {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if trimmed == "joyful" {
      return .playful
    }
    return SuggestionTone(rawValue: trimmed) ?? .neutral
  }
}
