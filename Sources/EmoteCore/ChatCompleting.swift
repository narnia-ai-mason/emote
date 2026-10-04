public struct ChatMessage: Codable, Equatable, Sendable {
  public var role: String
  public var content: String

  public init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

public struct ChatCompletionRequest: Equatable, Sendable {
  public var model: String
  public var messages: [ChatMessage]
  public var temperature: Double
  public var maxTokens: Int

  public init(
    model: String,
    messages: [ChatMessage],
    temperature: Double = 0.2,
    maxTokens: Int = 128
  ) {
    self.model = model
    self.messages = messages
    self.temperature = temperature
    self.maxTokens = maxTokens
  }
}

public struct ChatCompletionResponse: Equatable, Sendable {
  public var model: String
  public var content: String

  public init(model: String, content: String) {
    self.model = model
    self.content = content
  }
}

public protocol ChatCompleting: Sendable {
  func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
}
