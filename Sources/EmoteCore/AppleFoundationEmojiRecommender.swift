import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

public struct AppleFoundationEmojiRecommender: EmojiCandidateRetrieving {
  public static let defaultSlowThreshold = Duration.milliseconds(1_200)
  public static let defaultTemperature = 0.7

  public var temperature: Double
  private let debugHandler: (@Sendable (String) -> Void)?

  public init(
    temperature: Double = AppleFoundationEmojiRecommender.defaultTemperature,
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) {
    self.temperature = OpenRouterEmojiRecommender.clampedTemperature(temperature)
    self.debugHandler = debugHandler
  }

  public static func makeIfAvailable(
    temperature: Double = AppleFoundationEmojiRecommender.defaultTemperature,
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) -> AppleFoundationEmojiRecommender? {
    guard AppleFoundationAvailability.current.isAvailable else {
      return nil
    }
    prewarmIfAvailable()
    return AppleFoundationEmojiRecommender(
      temperature: temperature,
      debugHandler: debugHandler
    )
  }

  public static func prewarmIfAvailable() {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        Task {
          await AppleFoundationSessionPool.shared.prewarm()
        }
      }
    #endif
  }

  public static func prewarmAndWaitIfAvailable() async {
    guard AppleFoundationAvailability.current.isAvailable else {
      return
    }
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        await AppleFoundationSessionPool.shared.prewarm()
        try? await Task.sleep(for: .milliseconds(1_200))
      }
    #endif
  }

  public static func status() -> OnDeviceModelStatus {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return FoundationModelsStatus.current()
      }
    #endif
    return .unsupportedOS
  }

  public func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return try await AppleFoundationSessionPool.shared.candidates(
          query,
          limit: limit,
          temperature: temperature,
          debugHandler: debugHandler
        )
      }
    #endif
    throw EmojiRecommendationError.onDeviceUnavailable(
      OnDeviceModelStatus.unsupportedOS.summary
    )
  }
}

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  private enum FoundationModelsStatus {
    static func current() -> OnDeviceModelStatus {
      switch SystemLanguageModel.default.availability {
      case .available:
        .available
      case .unavailable(.deviceNotEligible):
        .deviceNotEligible
      case .unavailable(.appleIntelligenceNotEnabled):
        .appleIntelligenceNotEnabled
      case .unavailable(.modelNotReady):
        .modelNotReady
      case .unavailable(let reason):
        .unavailable("Apple Intelligence isn't available (\(String(describing: reason))).")
      }
    }
  }

  @available(macOS 26.0, *)
  @Generable
  private struct AppleEmojiPicks {
    @Guide(
      description: "Twelve distinct commonly used emoji characters with no repeats and no skin-tone variants",
      .count(12)
    )
    var emojis: [String]
  }

  @available(macOS 26.0, *)
  actor AppleFoundationSessionPool {
    static let shared = AppleFoundationSessionPool()

    private var spare: LanguageModelSession?
    private var spareWarmed = false

    func prewarm() {
      guard FoundationModelsStatus.current().isAvailable else {
        return
      }
      if spare == nil {
        spare = makeSession()
      }
      spare?.prewarm(promptPrefix: Prompt("Recommend emojis that best fit"))
      spareWarmed = true
    }

    func candidates(
      _ query: RetrievalQuery,
      limit: Int,
      temperature: Double,
      debugHandler: (@Sendable (String) -> Void)?
    ) async throws -> [ScoredEmojiCandidate] {
      let pool = max(12, limit * 2)
      let checkout = takeSession()
      debugHandler?(
        checkout.warm
          ? "Using a prewarmed on-device session."
          : "Starting a cold on-device session."
      )
      let first = try await generate(
        session: checkout.session,
        query: query,
        count: pool,
        extraInstruction: nil,
        temperature: temperature,
        debugHandler: debugHandler
      )
      let recommendations = parsed(first, limit: limit)

      return recommendations.enumerated().map { offset, recommendation in
        ScoredEmojiCandidate(
          recommendation: recommendation,
          score: Float(limit - offset)
        )
      }
    }

    private func takeSession() -> (session: LanguageModelSession, warm: Bool) {
      let session = spare ?? makeSession()
      let warm = spare != nil && spareWarmed
      spare = makeSession()
      spare?.prewarm(promptPrefix: Prompt("Recommend emojis that best fit"))
      spareWarmed = true
      return (session, warm)
    }

    private func makeSession() -> LanguageModelSession {
      LanguageModelSession(
        model: SystemLanguageModel.default,
        instructions: EmojiRecommendationPrompt.instructions
      )
    }

    private func generate(
      session: LanguageModelSession,
      query: RetrievalQuery,
      count: Int,
      extraInstruction: String?,
      temperature: Double,
      debugHandler: (@Sendable (String) -> Void)?
    ) async throws -> [String] {
      let status = FoundationModelsStatus.current()
      guard status.isAvailable else {
        throw EmojiRecommendationError.onDeviceUnavailable(status.summary)
      }

      let prompt = EmojiRecommendationPrompt.userPrompt(
        query: query,
        count: count,
        extraInstruction: extraInstruction,
        asksForJSON: false
      )
      debugHandler?("Requesting SystemLanguageModel.default on-device.")
      let options = GenerationOptions(
        temperature: temperature,
        maximumResponseTokens: 192
      )
      let started = ContinuousClock.now
      do {
        let response = try await session.respond(
          to: prompt,
          generating: AppleEmojiPicks.self,
          options: options
        )
        let elapsed = ContinuousClock.now - started
        debugHandler?("On-device finished in \(elapsed.milliseconds) ms.")
        debugHandler?("On-device emojis: \(response.content.emojis.joined(separator: " "))")
        return response.content.emojis
      } catch {
        let elapsed = ContinuousClock.now - started
        debugHandler?("On-device failed after \(elapsed.milliseconds) ms.")
        throw EmojiRecommendationError.requestFailed(error.localizedDescription)
      }
    }

    private func parsed(_ raw: [String], limit: Int) -> [EmojiRecommendation] {
      var seen = Set<String>()
      var results: [EmojiRecommendation] = []
      for item in raw {
        if let recommendation = EmojiCatalog.recommendation(matching: item),
          seen.insert(recommendation.emoji).inserted
        {
          results.append(recommendation)
          if results.count == limit {
            break
          }
        }
      }
      if results.count < limit {
        let leftover = EmojiResponseParser.recommendations(
          from: raw.joined(separator: " "),
          limit: limit
        )
        for recommendation in leftover where seen.insert(recommendation.emoji).inserted {
          results.append(recommendation)
          if results.count == limit {
            break
          }
        }
      }
      return results
    }
  }
#endif
