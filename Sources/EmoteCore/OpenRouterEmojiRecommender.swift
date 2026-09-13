import Foundation

public struct OpenRouterEmojiRecommender: EmojiCandidateRetrieving {
  public static let defaultModel = "openrouter/free"
  public static let defaultFallbackModels: [String] = []
  public static let recommendedModels = [
    "openrouter/free",
    "nex-agi/nex-n2.5-mini:free",
  ]
  public static let defaultTemperature = 0.2

  private let client: any ChatCompleting
  public let model: String
  public let fallbackModels: [String]
  public let temperature: Double
  private let debugHandler: (@Sendable (String) -> Void)?

  public init(
    client: any ChatCompleting,
    model: String = OpenRouterEmojiRecommender.defaultModel,
    fallbackModels: [String] = OpenRouterEmojiRecommender.defaultFallbackModels,
    temperature: Double = OpenRouterEmojiRecommender.defaultTemperature,
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) {
    self.client = client
    self.model = model
    self.fallbackModels = fallbackModels
    self.temperature = Self.clampedTemperature(temperature)
    self.debugHandler = debugHandler
  }

  public static func live(
    environment: [String: String] = DotEnv.load(),
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) throws -> OpenRouterEmojiRecommender {
    guard
      let apiKey = environment["OPENROUTER_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw EmojiRecommendationError.missingAPIKey
    }

    let model = environment["OPENROUTER_MODEL"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = (model?.isEmpty == false) ? model! : defaultModel

    let temperature = environment["EMOTE_TEMPERATURE"]
      .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

    return OpenRouterEmojiRecommender(
      client: OpenRouterClient(apiKey: apiKey),
      model: resolvedModel,
      fallbackModels: modelList(environment["OPENROUTER_FALLBACK_MODELS"]),
      temperature: temperature ?? defaultTemperature,
      debugHandler: debugHandler
    )
  }

  public func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    let first = try await complete(
      query: query,
      count: limit,
      extraInstruction: nil,
      retryOnEmpty: true
    )
    var recommendations = EmojiResponseParser.recommendations(
      from: first.content,
      limit: limit
    )

    if recommendations.isEmpty {
      debugHandler?(
        "First response had \(recommendations.count)/\(limit) catalog emojis; retrying."
      )
      do {
        let retry = try await complete(
          query: query,
          count: limit,
          extraInstruction: EmojiRecommendationPrompt.retryInstruction(missing: limit),
          retryOnEmpty: false
        )
        for recommendation in EmojiResponseParser.recommendations(
          from: retry.content,
          limit: limit
        ) where !recommendations.contains(where: { $0.emoji == recommendation.emoji }) {
          recommendations.append(recommendation)
          if recommendations.count == limit {
            break
          }
        }
      } catch {
        debugHandler?("Retry failed: \(error.localizedDescription)")
      }
    }

    return recommendations.enumerated().map { offset, recommendation in
      ScoredEmojiCandidate(
        recommendation: recommendation,
        score: Float(limit - offset)
      )
    }
  }

  private func complete(
    query: RetrievalQuery,
    count: Int,
    extraInstruction: String?,
    retryOnEmpty: Bool
  ) async throws -> ChatCompletionResponse {
    let request = ChatCompletionRequest(
      model: model,
      fallbackModels: fallbackModels,
      messages: [
        ChatMessage(role: "system", content: EmojiRecommendationPrompt.jsonInstructions),
        ChatMessage(
          role: "user",
          content: EmojiRecommendationPrompt.userPrompt(
            query: query,
            count: count,
            extraInstruction: extraInstruction,
            asksForJSON: true
          )
        ),
      ],
      temperature: temperature
    )
    debugHandler?("Requesting \(model) via OpenRouter.")
    do {
      return finish(try await client.complete(request))
    } catch EmojiRecommendationError.emptyModelResponse where retryOnEmpty {
      debugHandler?("Empty response; retrying the request.")
      return finish(try await client.complete(request))
    } catch {
      for fallback in fallbackModels where fallback != model {
        debugHandler?("\(model) failed; trying \(fallback).")
        var retry = request
        retry.model = fallback
        retry.fallbackModels = []
        do {
          return finish(try await client.complete(retry))
        } catch {
          debugHandler?("\(fallback) failed: \(error.localizedDescription)")
        }
      }
      throw error
    }
  }

  private func finish(_ response: ChatCompletionResponse) -> ChatCompletionResponse {
    debugHandler?("Model used: \(response.model)")
    debugHandler?("Raw response: \(response.content)")
    return response
  }

  public static func clampedTemperature(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  private static func modelList(_ raw: String?) -> [String] {
    guard let raw else {
      return []
    }
    return raw
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

}
