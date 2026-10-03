import EmoteCore
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

public enum GemmaEmojiEngine {
  private static let cache = GemmaModelCache()
  private static let loadedFlag = LoadedFlag()

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
    let prompt = situation.instructions + "\nDo not think out loud.\n\n" + situation.message
    let reply = try await container.perform { (context: ModelContext) -> String in
      let prepared = try await context.processor.prepare(
        input: UserInput(
          prompt: prompt,
          additionalContext: ["enable_thinking": false]
        )
      )
      let suffix = GemmaEmojiEngine.generationSuffix(prepared: prepared, tokenizer: context.tokenizer)
      let extraIDs = context.tokenizer.encode(text: suffix, addSpecialTokens: false)
      let input = GemmaEmojiEngine.appending(extraIDs, to: prepared)
      let stream = try generate(
        input: input,
        parameters: GenerateParameters(maxTokens: 80, temperature: 0.2),
        context: context
      )
      var text = ""
      for await event in stream {
        if let chunk = event.chunk {
          text += chunk
        }
      }
      return text
    }
    let recommendations = EmojiResponseParser.recommendations(
      from: "{\"emojis\":[" + reply,
      limit: 10
    )
    guard !recommendations.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    return recommendations
  }

  private static func generationSuffix(prepared: LMInput, tokenizer: any MLXLMCommon.Tokenizer) -> String {
    let rendered = tokenizer.decode(
      tokenIds: prepared.text.tokens.asArray(Int.self),
      skipSpecialTokens: false
    )
    var suffix = ""
    if !rendered.contains("<|turn>model") {
      suffix += "<|turn>model\n"
    }
    suffix += "<|channel>thought\n<channel|>{\"emojis\":["
    return suffix
  }

  private static func appending(_ tokenIDs: [Int], to prepared: LMInput) -> LMInput {
    let tokens = prepared.text.tokens
    let extra = MLXArray(tokenIDs.map(Int32.init))
    let merged: MLXArray
    if tokens.ndim == 2 {
      merged = concatenated([tokens, extra.reshaped(1, tokenIDs.count)], axis: 1)
    } else {
      merged = concatenated([tokens, extra], axis: 0)
    }
    return LMInput(
      text: .init(tokens: merged),
      image: prepared.image,
      video: prepared.video,
      audio: prepared.audio
    )
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
