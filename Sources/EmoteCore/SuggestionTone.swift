import Foundation

public enum SuggestionTone: String, CaseIterable, Sendable {
  case neutral
  case dry
  case warm
  case joyful

  public static func resolve(_ raw: String?) -> SuggestionTone {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return SuggestionTone(rawValue: trimmed) ?? .neutral
  }
}
