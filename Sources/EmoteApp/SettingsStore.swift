import EmoteCore
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  @Published var engine: RecommendationEngine {
    didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine) }
  }

  @Published var apiKey: String {
    didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
  }

  @Published var apiBaseURL: String {
    didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
  }

  @Published var apiModel: String {
    didSet { UserDefaults.standard.set(apiModel, forKey: Keys.apiModel) }
  }

  @Published var tone: String {
    didSet {
      let resolved = SuggestionTone.resolve(tone).rawValue
      if resolved != tone {
        tone = resolved
        return
      }
      UserDefaults.standard.set(resolved, forKey: Keys.tone)
    }
  }

  @Published var hotkey: HotkeyBinding {
    didSet { persistHotkey() }
  }

  private init() {
    let defaults = UserDefaults.standard
    if let storedEngine = defaults.string(forKey: Keys.engine),
      let engine = RecommendationEngine(rawValue: storedEngine)
    {
      self.engine = engine
    } else {
      engine = .gemma4
    }
    apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
    apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? APIEmojiEngine.defaultBaseURL
    apiModel = defaults.string(forKey: Keys.apiModel) ?? APIEmojiEngine.defaultModel
    tone = SuggestionTone.resolve(defaults.string(forKey: Keys.tone)).rawValue
    if let data = defaults.data(forKey: Keys.hotkey),
      let stored = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    {
      hotkey = stored
    } else {
      hotkey = .default
    }
  }

  private func persistHotkey() {
    if let data = try? JSONEncoder().encode(hotkey) {
      UserDefaults.standard.set(data, forKey: Keys.hotkey)
    }
  }

  private enum Keys {
    static let engine = "emote.engine"
    static let apiKey = "emote.apiKey"
    static let apiBaseURL = "emote.apiBaseURL"
    static let apiModel = "emote.apiModel"
    static let tone = "emote.tone"
    static let hotkey = "emote.hotkey"
  }
}
