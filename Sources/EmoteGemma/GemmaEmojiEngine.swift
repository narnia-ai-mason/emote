import EmoteCore
import Foundation
import HuggingFace
import MLX
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

public enum GemmaEmojiEngine {
  private static let cache = GemmaModelCache()
  private static let schema = EmojiSchema()
  private static let loadedFlag = LoadedFlag()
  private static let emojiSchema = """
    {"type":"object","properties":{"emojis":{"type":"array","minItems":5,"maxItems":10,"items":{"type":"string"}}},"required":["emojis"],"additionalProperties":false}
    """

  public static func isModelLoaded() -> Bool {
    loadedFlag.get()
  }

  public static func recommend(_ situation: WritingSituation) async throws -> [EmojiRecommendation] {
    try GemmaMetalLibrary.prepare()
    guard let directory = GemmaModelFiles.modelDirectory() else {
      throw EmojiRecommendationError.notConfigured(
        "Download Gemma 4 in Settings."
      )
    }
    let container = try await cache.load(directory: directory)
    loadedFlag.set()
    let reply = try await container.perform { (context: ModelContext) -> String in
      let prepared = try await context.processor.prepare(
        input: UserInput(
          chat: [
            .system(situation.instructions),
            .user(situation.message),
          ],
          additionalContext: ["enable_thinking": false]
        )
      )
      let guide = try schema.guide(tokenizer: context.tokenizer, jsonSchema: emojiSchema)
      var text = ""
      try GuidedGenerationLoop.run(
        input: prepared,
        context: context,
        constraint: guide.constraint,
        maxTokens: 160,
        vocabSize: guide.vocabSize
      ) { delta in
        text += delta
        return true
      }
      return text
    }
    let recommendations = EmojiResponseParser.recommendations(from: reply, limit: 10)
    guard !recommendations.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    return recommendations
  }
}

enum GemmaMetalLibrary {
  static func prepare() throws {
    if GPU.metallib != nil { return }
    let besideExecutable = Bundle.main.executableURL?
      .deletingLastPathComponent()
      .appendingPathComponent("mlx.metallib")
    let inResources = Bundle.main.resourceURL?.appendingPathComponent("mlx.metallib")
    for case let url? in [besideExecutable, inResources]
    where FileManager.default.fileExists(atPath: url.path) {
      GPU.metallib = url
      return
    }
    throw EmojiRecommendationError.notConfigured(
      "Gemma 4 could not start. The Metal library is missing."
    )
  }
}

private final class EmojiSchema: @unchecked Sendable {
  private let lock = NSLock()
  private var grammarTokenizer: GrammarTokenizer?
  private var vocabSize = 0

  func guide(tokenizer: any MLXLMCommon.Tokenizer, jsonSchema: String) throws -> (
    constraint: GrammarConstraint, vocabSize: Int
  ) {
    lock.lock()
    defer { lock.unlock() }
    let compiledTokenizer: GrammarTokenizer
    if let grammarTokenizer {
      compiledTokenizer = grammarTokenizer
    } else {
      let vocab = TokenizerVocabExtractor.extractForGrammar(from: tokenizer)
      compiledTokenizer = try GrammarTokenizer(
        vocab: vocab.vocab,
        vocabType: vocab.vocabType,
        eosTokenId: Int32(tokenizer.eosTokenId ?? 0)
      )
      grammarTokenizer = compiledTokenizer
      vocabSize = compiledTokenizer.vocabSize
    }
    let constraint = try GrammarConstraint(
      tokenizer: compiledTokenizer,
      jsonSchema: jsonSchema,
      fastForward: true,
      hostTokenizer: tokenizer
    )
    return (constraint, vocabSize)
  }
}

private actor GemmaModelCache {
  private var container: ModelContainer?

  func load(directory: URL) async throws -> ModelContainer {
    if let container { return container }
    let configuration = ModelConfiguration(
      directory: directory,
      extraEOSTokens: ["<turn|>"]
    )
    let loaded = try await VLMModelFactory.shared.loadContainer(
      from: #hubDownloader(),
      using: #huggingFaceTokenizerLoader(),
      configuration: configuration
    )
    container = loaded
    return loaded
  }
}

private final class LoadedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func get() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }
}
