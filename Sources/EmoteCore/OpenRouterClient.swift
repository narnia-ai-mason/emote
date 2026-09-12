import Foundation

public struct OpenRouterClient: ChatCompleting {
  public static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

  private let apiKey: String
  private let endpoint: URL
  private let session: URLSession
  private let referer: String
  private let title: String

  public init(
    apiKey: String,
    endpoint: URL = OpenRouterClient.defaultEndpoint,
    session: URLSession = OpenRouterClient.makeSession(),
    referer: String = "https://github.com/minsikseo/emote",
    title: String = "Emote"
  ) {
    self.apiKey = apiKey
    self.endpoint = endpoint
    self.session = session
    self.referer = referer
    self.title = title
  }

  public static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration)
  }

  public func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
    do {
      return try await send(request)
    } catch let error as EmojiRecommendationError
      where request.disableReasoning && isReasoningRejected(error)
    {
      var fallback = request
      fallback.disableReasoning = false
      return try await send(fallback)
    }
  }

  private func send(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 15
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
    urlRequest.setValue(title, forHTTPHeaderField: "X-Title")
    urlRequest.httpBody = try JSONEncoder().encode(RequestBody(request))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw EmojiRecommendationError.requestFailed(error.localizedDescription)
    }

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    let body = String(data: data, encoding: .utf8) ?? ""
    if let apiError = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
      let message = apiError.error.message,
      !message.isEmpty
    {
      let metadata = apiError.error.metadata.map { " \($0)" } ?? ""
      throw EmojiRecommendationError.requestFailed(
        "HTTP \(statusCode): \(message)\(metadata)"
      )
    }

    guard (200...299).contains(statusCode) else {
      throw EmojiRecommendationError.requestFailed(
        body.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(body)"
      )
    }

    let decoded = try JSONDecoder().decode(SuccessEnvelope.self, from: data)
    let content = decoded.choices.first?.message.resolvedContent ?? ""
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EmojiRecommendationError.emptyModelResponse
    }

    return ChatCompletionResponse(
      model: decoded.model ?? request.model,
      content: content
    )
  }
}

private func isReasoningRejected(_ error: EmojiRecommendationError) -> Bool {
  guard case .requestFailed(let detail) = error else {
    return false
  }
  let text = detail.lowercased()
  return text.contains("reasoning") || text.contains("effort")
}

private struct RequestBody: Encodable {
  var model: String
  var models: [String]?
  var messages: [ChatMessage]
  var temperature: Double
  var max_tokens: Int
  var reasoning: Reasoning?
  var provider: Provider?

  init(_ request: ChatCompletionRequest) {
    model = request.model
    let chain = Array(
      ([request.model] + request.fallbackModels.filter { $0 != request.model }).prefix(3)
    )
    models = chain.count > 1 ? chain : nil
    messages = request.messages
    temperature = request.temperature
    max_tokens = request.maxTokens
    reasoning = request.disableReasoning ? Reasoning(effort: "none", exclude: true) : nil
    provider = request.sortByLatency ? Provider(sort: "latency") : nil
  }

  struct Reasoning: Encodable {
    var effort: String
    var exclude: Bool
  }

  struct Provider: Encodable {
    var sort: String
  }
}

private struct SuccessEnvelope: Decodable {
  var model: String?
  var choices: [Choice]

  struct Choice: Decodable {
    var message: Message
  }

  struct Message: Decodable {
    var content: FlexibleContent?
    var reasoning: String?

    var resolvedContent: String? {
      let text = content?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !text.isEmpty {
        return content?.text
      }
      let reasoning = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return reasoning.isEmpty ? nil : self.reasoning
    }
  }
}

private struct ErrorEnvelope: Decodable {
  var error: ErrorBody

  struct ErrorBody: Decodable {
    var message: String?
    var metadata: FlexibleMetadata?
  }
}

private struct FlexibleMetadata: Decodable, CustomStringConvertible {
  var raw: String

  var description: String { raw }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let object = try? container.decode([String: String].self) {
      raw = object
        .map { "\($0.key)=\($0.value)" }
        .sorted()
        .joined(separator: ", ")
      return
    }
    raw = ""
  }
}

private enum FlexibleContent: Decodable {
  case string(String)
  case parts([Part])

  struct Part: Decodable {
    var text: String?
  }

  var text: String {
    switch self {
    case .string(let value):
      value
    case .parts(let parts):
      parts.compactMap(\.text).joined()
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let parts = try? container.decode([Part].self) {
      self = .parts(parts)
      return
    }
    self = .string("")
  }
}
