import Darwin
import EmoteCore
import Foundation

@main
struct EmoteCLI {
  static func main() async {
    do {
      var arguments = Array(CommandLine.arguments.dropFirst())
      var debug = false
      var context: String?
      var modelOverride: String?
      var tone: String?

      while let option = arguments.first, option.hasPrefix("--") {
        switch option {
        case "--debug":
          debug = true
          arguments.removeFirst()
        case "--context":
          guard arguments.count >= 2, !arguments[1].isEmpty else {
            writeToStandardError(Self.usage)
            exit(EX_USAGE)
          }
          context = arguments[1]
          arguments.removeFirst(2)
        case "--model":
          guard arguments.count >= 2, !arguments[1].isEmpty else {
            writeToStandardError(Self.usage)
            exit(EX_USAGE)
          }
          modelOverride = arguments[1]
          arguments.removeFirst(2)
        case "--tone":
          guard arguments.count >= 2, !arguments[1].isEmpty else {
            writeToStandardError(Self.usage)
            exit(EX_USAGE)
          }
          tone = arguments[1]
          arguments.removeFirst(2)
        default:
          writeToStandardError(Self.usage)
          exit(EX_USAGE)
        }
      }

      let keyword = arguments.joined(separator: " ")
      guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        writeToStandardError(Self.usage)
        exit(EX_USAGE)
      }

      var environment = DotEnv.load()
      if let modelOverride {
        environment["OPENROUTER_MODEL"] = modelOverride
      }
      if tone == nil {
        tone = environment["EMOTE_TONE"]
      }

      let debugHandler: (@Sendable (String) -> Void)?
      if debug {
        debugHandler = { message in
          writeToStandardError("[openrouter] \(message)")
        }
      } else {
        debugHandler = nil
      }

      let retriever = try OpenRouterEmojiRecommender.live(
        environment: environment,
        debugHandler: debugHandler
      )
      writeToStandardError("Asking \(retriever.model) for 5 emojis.")

      let service = EmojiRecommendationService(retriever: retriever)
      let candidateHandler: (@Sendable ([ScoredEmojiCandidate]) -> Void)?
      if debug {
        candidateHandler = { candidates in
          writeToStandardError("--- Recommendations ---")
          for candidate in candidates {
            writeToStandardError(
              "\(String(format: "%.0f", candidate.score)): \(candidate.recommendation.emoji) — \(candidate.recommendation.description)"
            )
          }
          writeToStandardError("--- End recommendations ---")
        }
      } else {
        candidateHandler = nil
      }

      let result = try await service.recommend(
        for: keyword,
        context: context,
        tone: tone,
        candidateHandler: candidateHandler
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
      let data = try encoder.encode(result)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      writeToStandardError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static let usage =
    "Usage: EmoteCLI [--debug] [--model <openrouter-model-slug>] [--tone \"<style>\"] [--context \"<sentence>\"] \"<keyword>\""

  private static func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
}
