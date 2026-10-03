import Foundation

public enum ChatAPIEndpoint {
  public static func url(base: String, defaultBase: String) throws -> URL {
    var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      text = defaultBase
    }
    if !text.contains("://") {
      text = "https://" + text
    }
    while text.hasSuffix("/") {
      text.removeLast()
    }
    if !text.hasSuffix("/chat/completions") {
      text += "/chat/completions"
    }
    guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else {
      throw EmojiRecommendationError.notConfigured("The API base URL is not valid.")
    }
    return url
  }
}

public struct ChatAPIClient: ChatCompleting {
  private let apiKey: String
  private let endpoint: URL
  private let session: URLSession

  public init(
    apiKey: String,
    endpoint: URL,
    session: URLSession = ChatAPIClient.makeSession()
  ) {
    self.apiKey = apiKey
    self.endpoint = endpoint
    self.session = session
  }

  public static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 45
    return URLSession(configuration: configuration)
  }

  public func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 30
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(RequestBody(request))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw EmojiRecommendationError.requestFailed(error.localizedDescription)
    }

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    if let apiError = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
      let message = apiError.error.message,
      !message.isEmpty
    {
      throw EmojiRecommendationError.requestFailed("HTTP \(statusCode): \(message)")
    }

    guard (200...299).contains(statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw EmojiRecommendationError.requestFailed(
        body.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(body)"
      )
    }

    let decoded = try JSONDecoder().decode(SuccessEnvelope.self, from: data)
    let content = decoded.choices?.first?.message.resolvedContent ?? ""
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EmojiRecommendationError.emptyModelResponse
    }
    return ChatCompletionResponse(model: decoded.model ?? request.model, content: content)
  }
}

private struct RequestBody: Encodable {
  var model: String
  var messages: [ChatMessage]
  var temperature: Double
  var max_tokens: Int

  init(_ request: ChatCompletionRequest) {
    model = request.model
    messages = request.messages
    temperature = request.temperature
    max_tokens = request.maxTokens
  }
}

private struct SuccessEnvelope: Decodable {
  var model: String?
  var choices: [Choice]?

  struct Choice: Decodable {
    var message: Message
  }

  struct Message: Decodable {
    var content: FlexibleContent?

    var resolvedContent: String? {
      let text = content?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return text.isEmpty ? nil : content?.text
    }
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

private struct ErrorEnvelope: Decodable {
  var error: ErrorBody

  struct ErrorBody: Decodable {
    var message: String?
  }
}
