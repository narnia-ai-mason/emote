import AppKit
import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text("Emote")
            .font(.title2.weight(.semibold))
          Text(versionLabel)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Text(
        "Emoji suggestions that appear next to your cursor. Press a hotkey, pick one, and keep typing."
      )
      .fixedSize(horizontal: false, vertical: true)

      Text("On-device")
        .font(.headline)
      Text(
        "When you use On-device or Auto with Apple Intelligence, the sentence is sent to the model on this Mac. It does not go through Emote's servers. There are none."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Text("OpenRouter")
        .font(.headline)
      Text(
        "When you use OpenRouter or Auto falls back to it, the text around the cursor is sent to OpenRouter and whichever model you chose. Emote does not run those services and is not responsible for how they store or use that text. That is governed by OpenRouter and the model provider."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Link(
          "OpenRouter terms",
          destination: URL(string: "https://openrouter.ai/terms")!
        )
        Link(
          "OpenRouter privacy",
          destination: URL(string: "https://openrouter.ai/privacy")!
        )
      }
      .font(.callout)

      Text("License")
        .font(.headline)
      Text(
        "Emote is provided as-is, without warranty. You choose the engine. You are responsible for the text you send and for complying with Apple's and OpenRouter's terms."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(28)
    .frame(width: 460)
  }

  private var versionLabel: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version.map { "Version \($0)" } ?? "Development build"
  }
}
