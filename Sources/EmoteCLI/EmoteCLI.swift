import Darwin
import EmoteCore
import EmoteGemma
import Foundation

@main
struct EmoteCLI {
  static func main() async {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--situation" {
      arguments.removeFirst()
      await runSituation(arguments)
      return
    }
    do {
      arguments = Array(CommandLine.arguments.dropFirst())
      var debug = false
      var context: String?
      var modelOverride: String?
      var tone: String?
      var engine = RecommendationEngine.default

      while let option = arguments.first, option.hasPrefix("--") {
        switch option {
        case "--debug":
          debug = true
          arguments.removeFirst()
        case "--prewarm":
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
      if let engineOverride = environment["EMOTE_ENGINE"], engine == .default,
        let parsed = parseEngine(engineOverride)
      {
        engine = parsed
      }
      if tone == nil {
        tone = environment["EMOTE_TONE"]
      }
      _ = debug

      let sentence = context ?? keyword
      guard
        let situation = WritingSituation.resolve(
          text: sentence,
          selectedUTF16: sentence.utf16.count..<sentence.utf16.count,
          tone: tone
        )
      else {
        writeToStandardError("Nothing to recommend.")
        exit(EX_USAGE)
      }
      writeToStandardError("Asking \(engine.title) for emojis.")
      let recommendations: [EmojiRecommendation]
      if engine == .gemma4 {
        recommendations = try await GemmaEmojiEngine.recommend(situation)
      } else {
        recommendations = try await APIEmojiEngine.recommend(
          situation,
          baseURL: environment["EMOTE_API_BASE_URL"] ?? APIEmojiEngine.defaultBaseURL,
          apiKey: environment["EMOTE_API_KEY"] ?? environment["OPENAI_API_KEY"] ?? "",
          model: modelOverride ?? environment["EMOTE_API_MODEL"] ?? APIEmojiEngine.defaultModel
        )
      }
      print(recommendations.map(\.emoji).joined(separator: " "))
    } catch {
      writeToStandardError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static func runSituation(_ arguments: [String]) async {
    var arguments = arguments
    var tone: String?
    var selecting = false
    var engine: RecommendationEngine?
    while let option = arguments.first, option.hasPrefix("--") {
      switch option {
      case "--tone":
        guard arguments.count >= 2 else { return }
        tone = arguments[1]
        arguments.removeFirst(2)
      case "--select":
        selecting = true
        arguments.removeFirst()
      case "--engine":
        guard arguments.count >= 2, let parsed = parseEngine(arguments[1]) else {
          writeToStandardError(usage)
          exit(EX_USAGE)
        }
        engine = parsed
        arguments.removeFirst(2)
      default:
        writeToStandardError(usage)
        exit(EX_USAGE)
      }
    }
    let raw = arguments.joined(separator: " ")
    let text: String
    let range: Range<Int>
    if selecting {
      text = raw
      range = 0..<raw.utf16.count
    } else if let marker = raw.range(of: "‸") {
      let prefix = String(raw[..<marker.lowerBound])
      let suffix = String(raw[marker.upperBound...])
      text = prefix + suffix
      range = prefix.utf16.count..<(prefix.utf16.count)
    } else {
      text = raw
      let end = raw.utf16.count
      range = end..<end
    }
    guard let situation = WritingSituation.resolve(text: text, selectedUTF16: range, tone: tone) else {
      writeToStandardError("Nothing to recommend.")
      exit(EX_USAGE)
    }
    print(situation.mode.rawValue)
    print(situation.message)
    print("---")
    let started = ContinuousClock.now
    do {
      if engine == .gemma4 {
        let recommendations = try await GemmaEmojiEngine.recommend(situation)
        let elapsed = ContinuousClock.now - started
        print("gemma4 \(elapsed.milliseconds) ms")
        print(recommendations.map(\.emoji).joined(separator: " "))
        return
      }
      if engine == .api {
        let environment = DotEnv.load()
        let recommendations = try await APIEmojiEngine.recommend(
          situation,
          baseURL: environment["EMOTE_API_BASE_URL"] ?? APIEmojiEngine.defaultBaseURL,
          apiKey: environment["EMOTE_API_KEY"] ?? environment["OPENAI_API_KEY"] ?? "",
          model: environment["EMOTE_API_MODEL"] ?? APIEmojiEngine.defaultModel
        )
        let elapsed = ContinuousClock.now - started
        print("api \(elapsed.milliseconds) ms")
        print(recommendations.map(\.emoji).joined(separator: " "))
        return
      }
      let outcome = try await SituationRecommender(rank: embedRank).recommend(situation)
      let elapsed = ContinuousClock.now - started
      print("\(outcome.stage.rawValue) \(elapsed.milliseconds) ms")
      print(outcome.recommendations.map(\.emoji).joined(separator: " "))
      if !outcome.embedding.isEmpty {
        let shown = outcome.embedding.prefix(5).map { String(format: "%@ %.3f", $0.emoji, $0.score) }
        print("embedding \(shown.joined(separator: "  "))")
      }
    } catch {
      writeToStandardError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static func embedRank(_ query: String) async -> [RankedEmoji] {
    let python = ProcessInfo.processInfo.environment["EMOTE_EMBED_PYTHON"] ?? "python3"
    let script = FileManager.default.currentDirectoryPath + "/scripts/embed_rank.py"
    guard FileManager.default.fileExists(atPath: script) else { return [] }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [python, script, query]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return []
    }
    guard process.terminationStatus == 0 else { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    return text.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\t")
      guard fields.count == 2, let score = Double(fields[1]) else { return nil }
      return RankedEmoji(emoji: String(fields[0]), score: score)
    }
  }

  private static let usage =
    "Usage: EmoteCLI [--engine gemma4|api] [--model <model>] [--tone neutral|dry|warm|playful] [--context \"<sentence>\"] \"<keyword>\""

  private static func parseEngine(_ raw: String) -> RecommendationEngine? {
    switch raw.lowercased() {
    case "gemma", "gemma4":
      .gemma4
    case "api", "openai":
      .api
    default:
      nil
    }
  }

  private static func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
}

extension Duration {
  fileprivate var milliseconds: Int {
    let parts = components
    return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
  }
}
