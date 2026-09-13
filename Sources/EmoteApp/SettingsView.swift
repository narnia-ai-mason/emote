import AppKit
import ApplicationServices
import EmoteCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  @FocusState private var focusedField: SettingsField?
  @State private var resignToken = 0
  @State private var accessibilityTrusted = AXIsProcessTrusted()
  @State private var onDeviceStatus = OnDeviceModelStatus.current
  @State private var routing = AutoRoutingMemory.shared.snapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      settingsField("Engine") {
        Picker("Engine", selection: $store.engine) {
          ForEach(RecommendationEngine.allCases, id: \.self) { engine in
            Text(engine.title).tag(engine)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)

        Text(engineHelp)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if let summary = routing.summary {
          Text(summary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if routing.skippedForSlowness {
          Button("Use on-device again") {
            AutoRoutingMemory.shared.resetSkip()
            routing = AutoRoutingMemory.shared.snapshot
          }
        }
      }

      if store.engine != .openRouter {
        settingsField("Apple Intelligence") {
          if onDeviceStatus.isAvailable {
            Text("Ready.")
              .font(.callout)
              .foregroundStyle(.secondary)
          } else {
            Text(onDeviceStatus.summary)
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if onDeviceStatus.canOpenSystemSettings {
              Button("Open Settings…") {
                AppChrome.openAppleIntelligenceSettings()
              }
            }
          }
        }
      }

      if store.engine != .onDevice {
        settingsField("API key") {
          SecureField("OpenRouter API key", text: $store.apiKey)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .apiKey)
          Text(apiKeyHelp)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        settingsField("Model") {
          Picker("Model", selection: $store.model) {
            ForEach(OpenRouterEmojiRecommender.recommendedModels, id: \.self) { model in
              Text(Self.title(for: model)).tag(model)
            }
            if !OpenRouterEmojiRecommender.recommendedModels.contains(store.model) {
              Text("Custom").tag(store.model)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)

          TextField("openrouter/free", text: $store.model)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($focusedField, equals: .model)

          Text("Pick a model or paste any OpenRouter model id.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if store.model == OpenRouterEmojiRecommender.defaultModel {
            Text("Auto routing may pick a different free model each time. Pin a model for more consistent suggestions.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Link(
            "OpenRouter privacy settings",
            destination: URL(string: "https://openrouter.ai/settings/privacy")!
          )
          .font(.callout)
        }

        settingsField("Temperature") {
          HStack(spacing: 10) {
            Slider(value: $store.temperature, in: 0...1, step: 0.1)
            Text(store.temperature, format: .number.precision(.fractionLength(1)))
              .font(.body.monospacedDigit())
              .frame(width: 28, alignment: .trailing)
          }
          Text(temperatureHelp)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      settingsField("Tone") {
        TextField("e.g. warm and light", text: $store.tone)
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .tone)
      }

      settingsField("Hotkey") {
        HotkeyRecorder(binding: $store.hotkey)
        Text("Include Control, Option, Command, or fn (globe). Press Esc to cancel.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      settingsField("Accessibility") {
        if accessibilityTrusted {
          Text("Allowed.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
          Text("Emote needs Accessibility to read and type into other apps.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button("Allow…") {
            _ = FrontmostEditor.ensureTrusted()
            refreshAccessibility()
          }
        }
      }
    }
    .padding(28)
    .frame(minWidth: 520, maxWidth: 520)
    .background {
      ZStack {
        SettingsFocusSink(resignToken: resignToken)
          .allowsHitTesting(false)
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture(perform: resignFocus)
      }
    }
    .onAppear {
      refreshAccessibility()
      refreshRouting()
      resignFocus()
    }
    .onChange(of: store.engine) { _, _ in
      resignFocus()
    }
    .onChange(of: store.hotkey) { _, hotkey in
      HotKeyMonitor.shared.register(hotkey)
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      refreshAccessibility()
      refreshRouting()
    }
  }

  private func settingsField<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture(perform: resignFocus)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var engineHelp: String {
    switch store.engine {
    case .auto:
      "Needs Apple Intelligence or an OpenRouter API key. Uses on-device when it's ready and fast enough."
    case .onDevice:
      "Needs Apple Intelligence. No API key."
    case .openRouter:
      "Needs an OpenRouter API key. Apple Intelligence can stay off."
    }
  }

  private var temperatureHelp: String {
    switch store.engine {
    case .auto:
      "Applies to OpenRouter. On-device stays at 0.7."
    case .openRouter, .onDevice:
      "Lower is more consistent. Higher is more varied. Even at 0, results can still change."
    }
  }

  private var apiKeyHelp: String {
    if store.engine == .auto && onDeviceStatus.isAvailable {
      return "Optional. Used when on-device is unavailable or too slow."
    }
    return "An API key is required to get recommendations."
  }

  private static func title(for model: String) -> String {
    switch model {
    case "openrouter/free":
      return "Auto routing"
    case "nex-agi/nex-n2.5-mini:free":
      return "Nex N2.5 Mini"
    default:
      return model
    }
  }

  private func refreshAccessibility() {
    accessibilityTrusted = AXIsProcessTrusted()
  }

  private func refreshRouting() {
    onDeviceStatus = OnDeviceModelStatus.current
    routing = AutoRoutingMemory.shared.snapshot
  }

  private func resignFocus() {
    focusedField = nil
    resignToken += 1
  }
}

private enum SettingsField: Hashable {
  case apiKey
  case model
  case tone
}

private struct SettingsFocusSink: NSViewRepresentable {
  var resignToken: Int

  func makeNSView(context: Context) -> FocusSinkView {
    FocusSinkView()
  }

  func updateNSView(_ nsView: FocusSinkView, context: Context) {
    guard resignToken > 0 else {
      return
    }
    nsView.window?.makeFirstResponder(nsView)
  }
}

private final class FocusSinkView: NSView {
  override var acceptsFirstResponder: Bool { true }
}
