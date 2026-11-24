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
  private static let tokenTable = EmojiTokenTableCache()
  private static let distributionCache = RecentDistributionCache()
  private static let loadedFlag = LoadedFlag()

  public static func isModelLoaded() -> Bool {
    loadedFlag.get()
  }

  public static func recommend(_ situation: WritingSituation) async throws -> [EmojiRecommendation] {
    let cacheKey = "\(situation.mode.rawValue)|\(situation.message)"
    if let resampled = await distributionCache.resampleIfRecent(for: cacheKey) {
      return resampled
    }

    try GemmaMetalLibrary.prepare()
    guard let directory = GemmaModelFiles.modelDirectory() else {
      throw EmojiRecommendationError.notConfigured(
        "Download Gemma 4 in Settings."
      )
    }
    let container = try await cache.load(directory: directory)
    loadedFlag.set()

    let instructions = onePassInstructions(for: situation.mode)
    let distribution = try await container.perform { (context: ModelContext) -> [ScoredEmoji] in
      let table = tokenTable.table(for: context.tokenizer)
      let prepared = try await context.processor.prepare(
        input: UserInput(
          chat: [
            .system(instructions),
            .user(situation.message),
          ],
          additionalContext: ["enable_thinking": false]
        )
      )
      let kvCache = try context.model.newCache(parameters: nil)
      let logits: MLXArray
      switch try context.model.prepare(
        prepared,
        cache: kvCache,
        state: nil,
        prefill: .init(stepSize: PrefillParameters.defaultStepSize)
      ) {
      case .tokens(let tokens):
        logits = context.model(tokens[text: .newAxis], cache: kvCache, state: nil).logits
      case .logits(let out):
        logits = out.logits
      }

      let lastLogits: MLXArray
      if logits.ndim == 3 {
        lastLogits = logits[0, -1, 0...]
      } else if logits.ndim == 2 {
        lastLogits = logits[-1, 0...]
      } else {
        lastLogits = logits
      }

      // Slice only emoji token logits before softmax so non-emoji vocab leakage cannot skew probabilities.
      let emojiLogits = lastLogits[table.flatTokenIDs].asType(.float32)
      eval(emojiLogits)
      let values = emojiLogits.asArray(Float.self)

      var entries: [(EmojiRecommendation, [Float])] = []
      entries.reserveCapacity(table.entries.count)
      for entry in table.entries {
        var group: [Float] = []
        group.reserveCapacity(entry.count)
        for offset in entry.start..<(entry.start + entry.count) where offset < values.count {
          group.append(values[offset])
        }
        entries.append((entry.recommendation, group))
      }
      return EmojiDistributionSampler.normalize(entries: entries)
    }

    let recommendations = await distributionCache.storeAndSample(
      key: cacheKey,
      distribution: distribution
    )
    guard !recommendations.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    return recommendations
  }

  private static func onePassInstructions(for mode: WritingSituation.Mode) -> String {
    switch mode {
    case .heading:
      return
        "You recommend one emoji a person would place before a section heading. Pick a representative mark for the section's topic, not the emotion of the following sentence. If the next sentence is empty, use only the heading. Match the requested tone. Reply with a single emoji character only, nothing else."
    case .sentence:
      return
        "You recommend one emoji a person would place after a sentence while writing. Prefer the writer's intent over a literal picture of one word. Match the requested tone. Reply with a single emoji character only, nothing else."
    case .word:
      return
        "You recommend one emoji a person would place next to a short span while writing. Prefer the sense of that span over a picture of one unrelated noun. Match the requested tone. Reply with a single emoji character only, nothing else."
    }
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

private struct EmojiTokenTable {
  struct Entry {
    let recommendation: EmojiRecommendation
    let start: Int
    let count: Int
  }

  let flatTokenIDs: MLXArray
  let entries: [Entry]
}

private final class EmojiTokenTableCache: @unchecked Sendable {
  private let lock = NSLock()
  private var cached: EmojiTokenTable?

  func table(for tokenizer: any MLXLMCommon.Tokenizer) -> EmojiTokenTable {
    lock.lock()
    defer { lock.unlock() }
    if let cached { return cached }

    // shortcut: single-token emojis only (1,135/1,914 in Gemma 4), add trie expansion for ZWJ/flags/multi-token emojis next.
    let spacePrefix = "\u{2581}"
    var flatIDs: [Int32] = []
    var entries: [EmojiTokenTable.Entry] = []
    entries.reserveCapacity(EmojiCatalog.all.count)

    for rec in EmojiCatalog.all {
      let stripped = stripVariationSelectors(rec.emoji)
      let variants = Set([rec.emoji, stripped, spacePrefix + rec.emoji, spacePrefix + stripped])
      var ids: [Int32] = []
      for variant in variants {
        if let id = tokenizer.convertTokenToId(variant), id >= 0 {
          ids.append(Int32(id))
        }
      }
      if !ids.isEmpty {
        let start = flatIDs.count
        flatIDs.append(contentsOf: ids)
        entries.append(EmojiTokenTable.Entry(recommendation: rec, start: start, count: ids.count))
      }
    }

    let built = EmojiTokenTable(flatTokenIDs: MLXArray(flatIDs), entries: entries)
    cached = built
    return built
  }

  private func stripVariationSelectors(_ text: String) -> String {
    String(text.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E })
  }
}

private actor RecentDistributionCache {
  private static let ttl: Duration = .seconds(30)

  private var lastKey: String?
  private var lastDistribution: [ScoredEmoji] = []
  private var shownEmojis: Set<String> = []
  private var updatedAt: ContinuousClock.Instant?

  func resampleIfRecent(for key: String) -> [EmojiRecommendation]? {
    guard key == lastKey,
      let updatedAt,
      ContinuousClock.now - updatedAt <= Self.ttl,
      !lastDistribution.isEmpty
    else { return nil }

    var picked = EmojiDistributionSampler.sample(
      from: lastDistribution,
      excluding: shownEmojis
    )
    if picked.isEmpty {
      shownEmojis.removeAll()
      picked = EmojiDistributionSampler.sample(from: lastDistribution)
    }
    if shownEmojis.count + picked.count >= lastDistribution.count {
      shownEmojis = Set(picked.map(\.emoji))
    } else {
      shownEmojis.formUnion(picked.map(\.emoji))
    }
    self.updatedAt = ContinuousClock.now
    return picked.isEmpty ? nil : picked
  }

  func storeAndSample(key: String, distribution: [ScoredEmoji]) -> [EmojiRecommendation] {
    let picked = EmojiDistributionSampler.sample(from: distribution)
    lastKey = key
    lastDistribution = distribution
    shownEmojis = Set(picked.map(\.emoji))
    updatedAt = ContinuousClock.now
    return picked
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
