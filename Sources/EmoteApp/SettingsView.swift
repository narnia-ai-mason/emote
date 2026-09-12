import AppKit
import ApplicationServices
import EmoteCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  @FocusState private var focusedField: SettingsField?
  @State private var resignToken = 0
  @State private var accessibilityTrusted = AXIsProcessTrusted()

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      settingsField("API key") {
        SecureField("OpenRouter API key", text: $store.apiKey)
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .apiKey)
        if store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("An API key is required to get recommendations.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
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
        Text("Lower is more consistent. Higher is more varied. Even at 0, results can still change.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
    .frame(width: 520)
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
      resignFocus()
    }
    .onChange(of: store.hotkey) { _, hotkey in
      HotKeyMonitor.shared.register(hotkey)
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      refreshAccessibility()
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
