import AppKit
import Carbon.HIToolbox
import EmoteCore
import SwiftUI

@main
struct EmoteApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @ObservedObject private var settings = SettingsStore.shared

  var body: some Scene {
    MenuBarExtra {
      Button("Recommend") {
        AppDelegate.shared?.recommend()
      }
      .applyHotkey(settings.hotkey)
      Divider()
      Button("Settings…") {
        AppChrome.showSettings()
      }
      .keyboardShortcut(",", modifiers: .command)
      Divider()
      Button("Quit") {
        NSApp.terminate(nil)
      }
    } label: {
      MenuBarLabel()
    }
    .menuBarExtraStyle(.menu)

    Window("Settings", id: "settings") {
      SettingsView(store: settings)
        .background(SettingsWindowChrome())
    }
    .windowResizability(.contentSize)
  }
}

private struct MenuBarLabel: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Label("Emote", systemImage: "face.smiling")
      .onAppear {
        AppChrome.openSettingsWindow = {
          openWindow(id: "settings")
        }
      }
  }
}

private struct SettingsWindowChrome: View {
  var body: some View {
    Color.clear
      .onAppear {
        AppChrome.becomeRegularApp()
      }
      .onDisappear {
        DispatchQueue.main.async {
          AppChrome.resignToMenuBarIfNeeded()
        }
      }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var shared: AppDelegate?

  private let hud = HUDController()
  private var recommendTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.shared = self
    NSApp.setActivationPolicy(.accessory)
    FrontmostEditor.startRemembering()
    hud.onDismiss = { [weak self] in
      self?.recommendTask?.cancel()
    }
    HotKeyMonitor.shared.onRecommend = { [weak self] in
      self?.recommend()
    }
    HotKeyMonitor.shared.onHUD = { [weak self] key in
      self?.hud.handle(key)
    }
    HotKeyMonitor.shared.register(SettingsStore.shared.hotkey)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    AppChrome.resignToMenuBarIfNeeded()
    return false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      AppChrome.showSettings()
    } else {
      AppChrome.becomeRegularApp()
    }
    return true
  }

  func recommend() {
    recommendTask?.cancel()
    hud.hide()

    guard FrontmostEditor.ensureTrusted() else {
      AppChrome.showSettings()
      hud.show(message: "Allow Accessibility in Settings", anchor: nil)
      return
    }

    let settings = SettingsStore.shared
    guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      AppChrome.showSettings()
      hud.show(message: "Add your API key in Settings", anchor: nil)
      return
    }

    guard let snapshot = FrontmostEditor.read(),
      let focus = TextFocus.resolve(text: snapshot.text, selectedUTF16: snapshot.selectedUTF16)
    else {
      hud.show(message: "Couldn't read the text", anchor: nil)
      return
    }

    var query = focus.query
    let tone = settings.tone.trimmingCharacters(in: .whitespacesAndNewlines)
    query.tone = tone.isEmpty ? nil : tone
    let anchor = FrontmostEditor.anchorRect(in: snapshot, focus: focus)
    let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = settings.model
    let fallbacks = settings.fallbackModels
    let keyword = clipped(query.focus, limit: 80)
    let context = query.context.map { clipped($0, limit: 240) }
    let queryTone = query.tone
    let queryKind = query.kind

    hud.showLoading(anchor: anchor)
    recommendTask = Task {
      do {
        let result = try await Task.detached {
          try await EmojiRecommendationService(
            retriever: OpenRouterEmojiRecommender(
              client: OpenRouterClient(apiKey: apiKey),
              model: model,
              fallbackModels: fallbacks
            )
          ).recommend(
            for: keyword,
            context: context,
            tone: queryTone,
            kind: queryKind
          )
        }.value
        guard !Task.isCancelled else {
          return
        }
        await MainActor.run {
          hud.show(
            recommendations: result.recommendations,
            anchor: anchor
          ) { recommendation in
            FrontmostEditor.apply(emoji: recommendation.emoji, to: snapshot, focus: focus)
          }
        }
      } catch {
        guard !Task.isCancelled else {
          return
        }
        await MainActor.run {
          hud.show(message: humanMessage(for: error), anchor: anchor)
        }
      }
    }
  }
}

private func clipped(_ text: String, limit: Int) -> String {
  guard text.count > limit else {
    return text
  }
  return String(text.prefix(limit))
}

private func humanMessage(for error: Error) -> String {
  guard let error = error as? EmojiRecommendationError else {
    return "Couldn't get recommendations"
  }
  switch error {
  case .emptyQuery:
    return "Nothing to recommend"
  case .missingAPIKey:
    return "Add your API key in Settings"
  case .requestFailed(let detail) where detail.contains("401"):
    return "That API key isn't valid"
  case .requestFailed(let detail)
  where detail.localizedCaseInsensitiveContains("timed out")
    || detail.localizedCaseInsensitiveContains("timeout"):
    return "The model took too long"
  case .requestFailed(let detail)
  where detail.localizedCaseInsensitiveContains("privacy")
    || detail.localizedCaseInsensitiveContains("data policy"):
    return "This model is blocked on your account"
  case .insufficientCandidates, .emptyModelResponse, .invalidModelResponse, .requestFailed:
    return "Couldn't get recommendations"
  }
}

private extension View {
  @ViewBuilder
  func applyHotkey(_ hotkey: HotkeyBinding) -> some View {
    if let key = hotkey.keyEquivalent {
      keyboardShortcut(key, modifiers: hotkey.eventModifiers)
    } else {
      self
    }
  }
}

private extension HotkeyBinding {
  var eventModifiers: SwiftUI.EventModifiers {
    var result: SwiftUI.EventModifiers = []
    if modifiers.contains(.control) { result.insert(.control) }
    if modifiers.contains(.option) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    if modifiers.contains(.command) { result.insert(.command) }
    return result
  }

  var keyEquivalent: KeyEquivalent? {
    if let character = layoutCharacter?.lowercased().first {
      return KeyEquivalent(character)
    }
    switch Int(keyCode) {
    case kVK_Space: return " "
    case kVK_Return, kVK_ANSI_KeypadEnter: return .return
    case kVK_Tab: return .tab
    case kVK_Escape: return .escape
    case kVK_Delete: return .delete
    case kVK_LeftArrow: return .leftArrow
    case kVK_RightArrow: return .rightArrow
    case kVK_UpArrow: return .upArrow
    case kVK_DownArrow: return .downArrow
    default:
      return nil
    }
  }
}
