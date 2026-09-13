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
      var engine = RecommendationEngine.default
      var prewarm = false

      while let option = arguments.first, option.hasPrefix("--") {
        switch option {
        case "--debug":
          debug = true
          arguments.removeFirst()
        case "--prewarm":
          prewarm = true
          arguments.removeFirst()
        case "--engine":
          guard arguments.count >= 2, let parsed = parseEngine(arguments[1]) else {
            writeToStandardError(Self.usage)
            exit(EX_USAGE)
          }
          engine = parsed
          arguments.removeFirst(2)
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
      if let engineOverride = environment["EMOTE_ENGINE"], engine == .default,
        let parsed = parseEngine(engineOverride)
      {
        engine = parsed
      }
      if tone == nil {
        tone = environment["EMOTE_TONE"]
      }

      let debugHandler: (@Sendable (String) -> Void)?
      if debug {
        debugHandler = { message in
          writeToStandardError("[emote] \(message)")
        }
      } else {
        debugHandler = nil
      }

      let model = environment["OPENROUTER_MODEL"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let temperature = environment["EMOTE_TEMPERATURE"]
        .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      let retriever = try EmojiRecommenderFactory.make(
        engine: engine,
        apiKey: environment["OPENROUTER_API_KEY"] ?? "",
        model: (model?.isEmpty == false) ? model! : OpenRouterEmojiRecommender.defaultModel,
        fallbackModels: fallbackModels(environment["OPENROUTER_FALLBACK_MODELS"]),
        temperature: temperature ?? OpenRouterEmojiRecommender.defaultTemperature,
        onDeviceTemperature: temperature ?? AppleFoundationEmojiRecommender.defaultTemperature,
        debugHandler: debugHandler
      )
      if prewarm {
        writeToStandardError("Prewarming the on-device session.")
        await AppleFoundationEmojiRecommender.prewarmAndWaitIfAvailable()
      }
      writeToStandardError("Asking \(engine.title) for 5 emojis.")

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
    "Usage: EmoteCLI [--debug] [--prewarm] [--engine auto|on-device|openrouter] [--model <openrouter-model-slug>] [--tone \"<style>\"] [--context \"<sentence>\"] \"<keyword>\""

  private static func parseEngine(_ raw: String) -> RecommendationEngine? {
    switch raw.lowercased() {
    case "auto":
      .auto
    case "on-device", "ondevice", "apple":
      .onDevice
    case "openrouter", "api":
      .openRouter
    default:
      nil
    }
  }

  private static func fallbackModels(_ raw: String?) -> [String] {
    guard let raw else {
      return OpenRouterEmojiRecommender.defaultFallbackModels
    }
    return raw
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
}
