import Foundation

public enum APIEmojiEngine {
  public static let defaultBaseURL = "https://api.openai.com/v1"
  public static let defaultModel = "gpt-4o-mini"

  public static func recommend(
    _ situation: WritingSituation,
    baseURL: String,
    apiKey: String,
    model: String,
    temperature: Double = 0.2
  ) async throws -> [EmojiRecommendation] {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw EmojiRecommendationError.missingAPIKey
    }
    let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelName.isEmpty else {
      throw EmojiRecommendationError.notConfigured("Set a model name in Settings.")
    }
    let endpoint = try ChatAPIEndpoint.url(base: baseURL, defaultBase: defaultBaseURL)
    let client = ChatAPIClient(apiKey: key, endpoint: endpoint)
    let response = try await client.complete(
      ChatCompletionRequest(
        model: modelName,
        messages: [
          ChatMessage(
            role: "system",
            content: situation.instructions + "\nDo not think out loud."
          ),
          ChatMessage(role: "user", content: situation.message),
        ],
        temperature: temperature,
        maxTokens: 160
      )
    )
    let recommendations = EmojiResponseParser.recommendations(from: response.content, limit: 10)
    guard !recommendations.isEmpty else {
      throw EmojiRecommendationError.insufficientCandidates(0)
    }
    return recommendations
  }
}
