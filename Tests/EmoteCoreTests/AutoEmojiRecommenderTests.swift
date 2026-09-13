import EmoteCore
import XCTest

final class AutoEmojiRecommenderTests: XCTestCase {
  func testOnDeviceDefaultTemperatureIsHigherThanOpenRouter() {
    XCTAssertEqual(AppleFoundationEmojiRecommender.defaultTemperature, 0.7)
    XCTAssertEqual(OpenRouterEmojiRecommender.defaultTemperature, 0.2)
    XCTAssertEqual(
      AppleFoundationEmojiRecommender().temperature,
      AppleFoundationEmojiRecommender.defaultTemperature
    )
  }

  func testUsesOnDeviceWhenItIsFastEnough() async throws {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let onDevice = RecordingStubRetriever(result: Self.five)
    let openRouter = RecordingStubRetriever(result: Self.other)

    let result = try await AutoEmojiRecommender(
      onDevice: onDevice,
      openRouter: openRouter,
      memory: memory,
      slowThreshold: .milliseconds(1_200),
      clock: ManualClock(steps: [
        .milliseconds(0),
        .milliseconds(400),
      ])
    ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)

    XCTAssertEqual(result.map(\.recommendation.emoji), Self.five.map(\.recommendation.emoji))
    XCTAssertEqual(onDevice.calls, 1)
    XCTAssertEqual(openRouter.calls, 0)
    XCTAssertEqual(memory.snapshot.lastBackend, "on-device")
    XCTAssertEqual(memory.snapshot.lastAppleMilliseconds, 400)
    XCTAssertFalse(memory.snapshot.skippedForSlowness)
  }

  func testKeepsASlowOnDeviceResultAndSkipsItNextTime() async throws {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let onDevice = RecordingStubRetriever(result: Self.five)
    let openRouter = RecordingStubRetriever(result: Self.other)

    let first = try await AutoEmojiRecommender(
      onDevice: onDevice,
      openRouter: openRouter,
      memory: memory,
      slowThreshold: .milliseconds(1_200),
      clock: ManualClock(steps: [
        .milliseconds(0),
        .milliseconds(1_800),
      ])
    ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)

    XCTAssertEqual(first.map(\.recommendation.emoji), Self.five.map(\.recommendation.emoji))
    XCTAssertTrue(memory.snapshot.skippedForSlowness)

    let second = try await AutoEmojiRecommender(
      onDevice: onDevice,
      openRouter: openRouter,
      memory: memory,
      clock: ManualClock(steps: [
        .milliseconds(0),
        .milliseconds(10),
      ])
    ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)

    XCTAssertEqual(second.map(\.recommendation.emoji), Self.other.map(\.recommendation.emoji))
    XCTAssertEqual(onDevice.calls, 1)
    XCTAssertEqual(openRouter.calls, 1)
    XCTAssertEqual(memory.snapshot.lastBackend, "OpenRouter")
  }

  func testFallsBackToOpenRouterWhenOnDeviceFails() async throws {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let onDevice = RecordingStubRetriever(
      error: EmojiRecommendationError.requestFailed("busy")
    )
    let openRouter = RecordingStubRetriever(result: Self.other)

    let result = try await AutoEmojiRecommender(
      onDevice: onDevice,
      openRouter: openRouter,
      memory: memory,
      clock: ManualClock(steps: [
        .milliseconds(0),
        .milliseconds(20),
      ])
    ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)

    XCTAssertEqual(result.map(\.recommendation.emoji), Self.other.map(\.recommendation.emoji))
    XCTAssertEqual(onDevice.calls, 1)
    XCTAssertEqual(openRouter.calls, 1)
    XCTAssertFalse(memory.snapshot.skippedForSlowness)
    XCTAssertEqual(memory.snapshot.lastBackend, "OpenRouter")
  }

  func testFallsBackWhenOnDeviceReturnsNoEmojis() async throws {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let onDevice = RecordingStubRetriever(result: [])
    let openRouter = RecordingStubRetriever(result: Self.other)

    let result = try await AutoEmojiRecommender(
      onDevice: onDevice,
      openRouter: openRouter,
      memory: memory,
      clock: ManualClock(steps: [
        .milliseconds(0),
        .milliseconds(80),
      ])
    ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)

    XCTAssertEqual(result.map(\.recommendation.emoji), Self.other.map(\.recommendation.emoji))
    XCTAssertEqual(openRouter.calls, 1)
  }

  func testThrowsWhenOnDeviceFailsAndThereIsNoAPIKey() async {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let onDevice = RecordingStubRetriever(
      error: EmojiRecommendationError.requestFailed("busy")
    )

    do {
      _ = try await AutoEmojiRecommender(
        onDevice: onDevice,
        openRouter: nil,
        memory: memory,
        clock: ManualClock(steps: [
          .milliseconds(0),
          .milliseconds(20),
        ])
      ).candidates(RetrievalQuery(focus: "hello", kind: .sentence), limit: 5)
      XCTFail("Expected on-device failure to surface without OpenRouter")
    } catch {
      XCTAssertEqual(
        error as? EmojiRecommendationError,
        .requestFailed("busy")
      )
    }
  }

  func testResetSkipLetsOnDeviceRunAgain() async throws {
    let memory = AutoRoutingMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    memory.recordOnDeviceSuccess(duration: .milliseconds(2_000), threshold: .milliseconds(1_200))
    XCTAssertTrue(memory.snapshot.skippedForSlowness)
    memory.resetSkip()
    XCTAssertFalse(memory.snapshot.skippedForSlowness)
    XCTAssertTrue(memory.shouldTryOnDevice)
  }

  private static let five = [
    candidate("🎉", "Party popper", 5),
    candidate("✨", "Sparkles", 4),
    candidate("😀", "Grinning face", 3),
    candidate("👏", "Clapping hands", 2),
    candidate("🙌", "Raising hands", 1),
  ]

  private static let other = [
    candidate("👍", "Thumbs up", 5),
    candidate("🙂", "Slightly smiling face", 4),
    candidate("🔥", "Fire", 3),
    candidate("💯", "Hundred points", 2),
    candidate("😎", "Smiling face with sunglasses", 1),
  ]

  private static func candidate(
    _ emoji: String,
    _ description: String,
    _ score: Float
  ) -> ScoredEmojiCandidate {
    ScoredEmojiCandidate(
      recommendation: EmojiRecommendation(emoji: emoji, description: description),
      score: score
    )
  }
}

private final class RecordingStubRetriever: EmojiCandidateRetrieving, @unchecked Sendable {
  private let result: [ScoredEmojiCandidate]
  private let error: Error?
  private(set) var calls = 0

  init(result: [ScoredEmojiCandidate] = [], error: Error? = nil) {
    self.result = result
    self.error = error
  }

  func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    calls += 1
    if let error {
      throw error
    }
    return result
  }
}

private struct ManualClock: AutoRoutingClock {
  private final class Storage: @unchecked Sendable {
    var remaining: [Duration]
    var now: ContinuousClock.Instant

    init(steps: [Duration]) {
      remaining = steps
      now = ContinuousClock.now
    }
  }

  private let storage: Storage

  init(steps: [Duration]) {
    storage = Storage(steps: steps)
  }

  var now: ContinuousClock.Instant {
    if let step = storage.remaining.first {
      storage.remaining.removeFirst()
      storage.now = storage.now.advanced(by: step)
    }
    return storage.now
  }
}
