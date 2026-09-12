import EmoteCore
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  @Published var apiKey: String {
    didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
  }

  @Published var model: String {
    didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
  }

  @Published var tone: String {
    didSet { UserDefaults.standard.set(tone, forKey: Keys.tone) }
  }

  @Published var hotkey: HotkeyBinding {
    didSet { persistHotkey() }
  }

  @Published var temperature: Double {
    didSet {
      let clamped = OpenRouterEmojiRecommender.clampedTemperature(temperature)
      if clamped != temperature {
        temperature = clamped
        return
      }
      UserDefaults.standard.set(clamped, forKey: Keys.temperature)
    }
  }

  var fallbackModels: [String] {
    let stored = UserDefaults.standard.string(forKey: Keys.fallbacks)?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
    if !stored.isEmpty {
      return stored
    }
    if model != OpenRouterEmojiRecommender.defaultModel {
      return [OpenRouterEmojiRecommender.defaultModel]
    }
    return []
  }

  private init() {
    let defaults = UserDefaults.standard
    apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
    model = defaults.string(forKey: Keys.model) ?? OpenRouterEmojiRecommender.defaultModel
    tone = defaults.string(forKey: Keys.tone) ?? ""
    if let data = defaults.data(forKey: Keys.hotkey),
      let stored = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    {
      hotkey = stored
    } else {
      hotkey = .default
    }
    if defaults.object(forKey: Keys.temperature) != nil {
      temperature = OpenRouterEmojiRecommender.clampedTemperature(
        defaults.double(forKey: Keys.temperature)
      )
    } else {
      temperature = OpenRouterEmojiRecommender.defaultTemperature
    }
  }

  private func persistHotkey() {
    if let data = try? JSONEncoder().encode(hotkey) {
      UserDefaults.standard.set(data, forKey: Keys.hotkey)
    }
  }

  private enum Keys {
    static let apiKey = "emote.apiKey"
    static let model = "emote.model"
    static let tone = "emote.tone"
    static let hotkey = "emote.hotkey"
    static let temperature = "emote.temperature"
    static let fallbacks = "emote.fallbacks"
  }
}
