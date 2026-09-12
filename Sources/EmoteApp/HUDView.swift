import EmoteCore
import SwiftUI

struct HUDView: View {
  var recommendations: [EmojiRecommendation]
  var selectedIndex: Int
  var isLoading: Bool
  var message: String?
  var onChoose: (Int) -> Void

  var body: some View {
    Group {
      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Finding…")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      } else if let message {
        Text(message)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary.opacity(0.7))
          .lineLimit(2)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
      } else {
        HStack(spacing: 2) {
          ForEach(Array(slots.enumerated()), id: \.offset) { index, emoji in
            Button {
              onChoose(index)
            } label: {
              Text(emoji)
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .opacity(isLoading ? 0.25 : 1)
                .background(
                  RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(index == selectedIndex && !isLoading
                      ? Color.primary.opacity(0.12)
                      : Color.clear)
                )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
      }
    }
    .background(
      .ultraThinMaterial,
      in: Capsule()
    )
    .overlay(
      Capsule()
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .fixedSize()
  }

  private var slots: [String] {
    recommendations.map(\.emoji)
  }
}
