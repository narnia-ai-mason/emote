import AppKit
import ApplicationServices
import EmoteCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  @ObservedObject private var gemma = GemmaModelStore.shared
  @State private var resignToken = 0
  @State private var accessibilityTrusted = AXIsProcessTrusted()

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      settingsField("Engine") {
        EnginePicker(engine: $store.engine)
          .frame(maxWidth: .infinity)

        Text(engineHelp)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if store.engine == .gemma4 {
        settingsField("Gemma 4") {
          GemmaDownloadSection(store: gemma)
        }
      }

      if store.engine == .api {
        settingsField("API") {
          APIFields(store: store)
        }
      }

      settingsField("Tone") {
        Picker("Tone", selection: $store.tone) {
          ForEach(SuggestionTone.allCases, id: \.rawValue) { tone in
            Text(tone.rawValue).tag(tone.rawValue)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
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
    case .gemma4:
      "Gemma 4 E4B runs on this Mac. Download it once in Settings."
    case .api:
      "Sends the sentence to an OpenAI-compatible chat API. OpenAI, OpenRouter, Groq, and Together all use this shape."
    }
  }

  private func refreshAccessibility() {
    accessibilityTrusted = AXIsProcessTrusted()
  }

  private func refreshRouting() {
    gemma.refresh()
  }

  private func resignFocus() {
    resignToken += 1
  }
}

private struct GemmaDownloadSection: View {
  @ObservedObject var store: GemmaModelStore

  var body: some View {
    if store.isReady {
      Text("Ready.")
        .font(.callout)
        .foregroundStyle(.secondary)
    } else if store.isDownloading {
      VStack(alignment: .leading, spacing: 8) {
        ProgressView(value: store.fraction)
        Text("받는 중 \(Int(store.fraction * 100))%")
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    } else {
      Text("처음 쓸 때는 Gemma 4 E4B를 이 Mac에 받아야 합니다. 약 5.2GB이고, 받은 뒤에는 이 앱 안에서만 씁니다.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let failure = store.failure {
        Text(failure)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button("모델 받기…") {
        store.confirmDownload = true
      }
      .confirmationDialog(
        "Gemma 4 E4B를 받을까요?",
        isPresented: $store.confirmDownload,
        titleVisibility: .visible
      ) {
        Button("받기") {
          store.startDownload()
        }
        Button("나중에", role: .cancel) {}
      } message: {
        Text("약 5.2GB를 받습니다. 받는 동안 진행률이 여기 표시됩니다.")
      }
    }
  }
}

private struct APIFields: View {
  @ObservedObject var store: SettingsStore

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Base URL", text: $store.apiBaseURL)
        .textFieldStyle(.roundedBorder)
      SecureField("API key", text: $store.apiKey)
        .textFieldStyle(.roundedBorder)
      TextField("Model", text: $store.apiModel)
        .textFieldStyle(.roundedBorder)
      Text("Base URL is the provider's /v1 root. Example: https://openrouter.ai/api/v1")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct EnginePicker: NSViewRepresentable {
  @Binding var engine: RecommendationEngine

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: RecommendationEngine.allCases.map(\.title),
      trackingMode: .selectOne,
      target: context.coordinator,
      action: #selector(Coordinator.changed(_:))
    )
    control.segmentStyle = .rounded
    control.segmentDistribution = .fillEqually
    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    control.setAccessibilityLabel("Engine")
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.onSelect = { engine = $0 }
    if let index = RecommendationEngine.allCases.firstIndex(of: engine) {
      control.selectedSegment = index
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var onSelect: ((RecommendationEngine) -> Void)?

    @objc func changed(_ sender: NSSegmentedControl) {
      let cases = RecommendationEngine.allCases
      guard cases.indices.contains(sender.selectedSegment) else {
        return
      }
      onSelect?(cases[sender.selectedSegment])
    }
  }
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
