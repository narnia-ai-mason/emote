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

      Text("API")
        .font(.headline)
      Text(
        "When you use API, the sentence is sent to the chat service in Settings. Emote does not run a server of its own."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Text("Gemma 4")
        .font(.headline)
      Text(
        "Gemma 4 E4B is downloaded once and then runs on this Mac. The sentence stays on this Mac."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Text("License")
        .font(.headline)
      Text(
        "Emote is provided as-is, without warranty. You choose the engine. Gemma 4 is used under its own license."
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
