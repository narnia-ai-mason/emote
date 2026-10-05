import AppKit
import Carbon.HIToolbox
import EmoteCore
import EmoteGemma
import os
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
      Button("About Emote") {
        AppChrome.showAbout()
      }
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

    Window("About Emote", id: "about") {
      AboutView()
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
        AppChrome.openAboutWindow = {
          openWindow(id: "about")
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
    let settings = SettingsStore.shared
    if !EngineRequirements.isReady(engine: settings.engine, apiKey: settings.apiKey) {
      AppChrome.showSettings()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    hud.hide()
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
      showFailure(
        "Allow Accessibility in Settings",
        anchor: nil,
        application: FrontmostEditor.currentExternalApp(),
        openSettings: true
      )
      return
    }

    let settings = SettingsStore.shared

    let snapshot = FrontmostEditor.read()
    if let snapshot, snapshot.caretIsOutsideText {
      showFailure(
        "This app hides text this far down",
        anchor: snapshot.caretScreenRect,
        snapshot: snapshot
      )
      return
    }

    guard let snapshot,
      let focus = TextFocus.resolve(text: snapshot.text, selectedUTF16: snapshot.selectedUTF16)
    else {
      showFailure(
        "Couldn't read the text",
        anchor: nil,
        application: FrontmostEditor.currentExternalApp()
      )
      return
    }

    let tone = settings.tone.trimmingCharacters(in: .whitespacesAndNewlines)
    let anchor = FrontmostEditor.anchorRect(in: snapshot, focus: focus)
    if settings.engine == .gemma4 {
      guard GemmaModelStore.shared.isReady else {
        showFailure(
          "Download Gemma 4 in Settings",
          anchor: anchor,
          snapshot: snapshot,
          openSettings: true
        )
        return
      }
      guard
        let situation = WritingSituation.resolve(
          text: snapshot.text,
          selectedUTF16: snapshot.selectedUTF16,
          tone: tone.isEmpty ? nil : tone,
          following: snapshot.following
        )
      else {
        showFailure("Nothing to recommend", anchor: anchor, snapshot: snapshot)
        return
      }
      hud.showLoading(
        anchor: anchor,
        message: GemmaEmojiEngine.isModelLoaded() ? "Finding…" : "Loading the model…"
      )
      recommendTask = Task {
        do {
          let recommendations = try await GemmaEmojiEngine.recommend(situation)
          guard !Task.isCancelled else { return }
          await MainActor.run {
            self.show(
              recommendations,
              situation: situation,
              anchor: anchor,
              snapshot: snapshot,
              focus: focus
            )
          }
        } catch {
          guard !Task.isCancelled else { return }
          let notice = humanMessage(for: error)
          let detail = recommendationErrorDetail(error)
          await MainActor.run {
            self.showFailure(
              notice,
              anchor: anchor,
              situation: situation,
              snapshot: snapshot,
              errorDetail: detail == notice ? nil : detail
            )
          }
        }
      }
      return
    }

    guard
      let situation = WritingSituation.resolve(
        text: snapshot.text,
        selectedUTF16: snapshot.selectedUTF16,
        tone: tone.isEmpty ? nil : tone,
        following: snapshot.following
      )
    else {
      showFailure("Nothing to recommend", anchor: anchor, snapshot: snapshot)
      return
    }
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      showFailure(
        "Add your API key in Settings",
        anchor: anchor,
        situation: situation,
        snapshot: snapshot,
        openSettings: true
      )
      return
    }
    let model = settings.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else {
      showFailure(
        "Set a model name in Settings",
        anchor: anchor,
        situation: situation,
        snapshot: snapshot,
        openSettings: true
      )
      return
    }
    hud.showLoading(anchor: anchor)
    let baseURL = settings.apiBaseURL
    recommendTask = Task {
      do {
        let recommendations = try await APIEmojiEngine.recommend(
          situation,
          baseURL: baseURL,
          apiKey: key,
          model: model
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
          self.show(
            recommendations,
            situation: situation,
            anchor: anchor,
            snapshot: snapshot,
            focus: focus
          )
        }
      } catch {
        guard !Task.isCancelled else { return }
        let notice = humanMessage(for: error)
        let detail = recommendationErrorDetail(error)
        await MainActor.run {
          self.showFailure(
            notice,
            anchor: anchor,
            situation: situation,
            snapshot: snapshot,
            errorDetail: detail == notice ? nil : detail
          )
        }
      }
    }
  }

  private func show(
    _ recommendations: [EmojiRecommendation],
    situation: WritingSituation,
    anchor: CGRect?,
    snapshot: FrontmostEditor.Snapshot,
    focus: TextFocus
  ) {
    hud.onResolution = { resolution, emojis in
      switch resolution {
      case .selected(let emoji, let index):
        recordRecommendation(
          situation: situation,
          recommendations: emojis,
          outcome: .selected,
          selected: emoji,
          selectedIndex: index,
          appName: snapshot.application?.localizedName,
          appBundleIdentifier: snapshot.application?.bundleIdentifier,
          caret: snapshot.caret
        )
      case .cancelled:
        recordRecommendation(
          situation: situation,
          recommendations: emojis,
          outcome: .cancelled,
          appName: snapshot.application?.localizedName,
          appBundleIdentifier: snapshot.application?.bundleIdentifier,
          caret: snapshot.caret
        )
      }
    }
    hud.show(recommendations: recommendations, anchor: anchor) { recommendation in
      FrontmostEditor.apply(emoji: recommendation.emoji, to: snapshot, focus: focus)
    }
  }

  private func showFailure(
    _ notice: String,
    anchor: CGRect?,
    situation: WritingSituation? = nil,
    snapshot: FrontmostEditor.Snapshot? = nil,
    application: NSRunningApplication? = nil,
    errorDetail: String? = nil,
    openSettings: Bool = false
  ) {
    if openSettings {
      AppChrome.showSettings()
    }
    let app = snapshot?.application ?? application
    recordRecommendation(
      situation: situation,
      recommendations: [],
      outcome: .failed,
      appName: app?.localizedName,
      appBundleIdentifier: app?.bundleIdentifier,
      notice: notice,
      errorDetail: errorDetail,
      caret: snapshot?.caret
    )
    hud.show(message: notice, anchor: anchor)
  }
}

private let recommendationLog = Logger(subsystem: "com.minsikseo.emote", category: "history")

private func recordRecommendation(
  situation: WritingSituation?,
  recommendations: [String],
  outcome: RecommendationRecord.Outcome,
  selected: String? = nil,
  selectedIndex: Int? = nil,
  appName: String? = nil,
  appBundleIdentifier: String? = nil,
  notice: String? = nil,
  errorDetail: String? = nil,
  caret: CaretDebug? = nil
) {
  let record = RecommendationRecord(
    mode: situation?.mode,
    message: situation?.message,
    recommendations: recommendations,
    outcome: outcome,
    selected: selected,
    selectedIndex: selectedIndex,
    appName: appName,
    appBundleIdentifier: appBundleIdentifier,
    notice: notice,
    errorDetail: errorDetail,
    caret: caret
  )
  do {
    try RecommendationHistory.append(record, to: RecommendationHistory.defaultFileURL())
  } catch {
    recommendationLog.error(
      "Failed to write recommendation history: \(error.localizedDescription, privacy: .public)"
    )
  }
}

private func recommendationErrorDetail(_ error: Error) -> String? {
  let text: String?
  if let error = error as? EmojiRecommendationError {
    text = error.errorDescription
  } else {
    text = error.localizedDescription
  }
  guard let text, !text.isEmpty else {
    return nil
  }
  return text
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
  case .missingAPIKey:
    return "Add your API key in Settings"
  case .notConfigured(let detail):
    return detail
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
  case .insufficientCandidates, .emptyModelResponse, .requestFailed:
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
