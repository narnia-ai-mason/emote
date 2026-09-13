public struct AutoEmojiRecommender: EmojiCandidateRetrieving {
  public var slowThreshold: Duration
  private let onDevice: (any EmojiCandidateRetrieving)?
  private let openRouter: (any EmojiCandidateRetrieving)?
  private let memory: AutoRoutingMemory
  private let clock: any AutoRoutingClock
  private let debugHandler: (@Sendable (String) -> Void)?

  public init(
    onDevice: (any EmojiCandidateRetrieving)?,
    openRouter: (any EmojiCandidateRetrieving)?,
    memory: AutoRoutingMemory = .shared,
    slowThreshold: Duration = AppleFoundationEmojiRecommender.defaultSlowThreshold,
    clock: any AutoRoutingClock = ContinuousClock(),
    debugHandler: (@Sendable (String) -> Void)? = nil
  ) {
    self.onDevice = onDevice
    self.openRouter = openRouter
    self.memory = memory
    self.slowThreshold = slowThreshold
    self.clock = clock
    self.debugHandler = debugHandler
  }

  public func candidates(
    _ query: RetrievalQuery,
    limit: Int
  ) async throws -> [ScoredEmojiCandidate] {
    if let onDevice, memory.shouldTryOnDevice {
      let started = clock.now
      do {
        let result = try await onDevice.candidates(query, limit: limit)
        let elapsed = clock.now - started
        memory.recordOnDeviceSuccess(duration: elapsed, threshold: slowThreshold)
        debugHandler?("On-device finished in \(elapsed.milliseconds) ms.")
        if elapsed > slowThreshold {
          debugHandler?(
            "On-device exceeded \(slowThreshold.milliseconds) ms; Auto will use OpenRouter next time."
          )
        }
        if !result.isEmpty {
          return result
        }
        debugHandler?("On-device returned no catalog emojis; trying OpenRouter.")
      } catch {
        memory.recordOnDeviceFailure()
        debugHandler?("On-device failed: \(error.localizedDescription)")
        if openRouter == nil {
          throw error
        }
      }
    } else if onDevice != nil {
      debugHandler?("Skipping on-device because the last run was too slow.")
    }

    guard let openRouter else {
      if onDevice == nil {
        throw EmojiRecommendationError.onDeviceUnavailable(
          OnDeviceModelStatus.current.summary
        )
      }
      throw EmojiRecommendationError.missingAPIKey
    }

    memory.recordOpenRouter()
    debugHandler?("Requesting OpenRouter.")
    return try await openRouter.candidates(query, limit: limit)
  }
}

public protocol AutoRoutingClock: Sendable {
  var now: ContinuousClock.Instant { get }
}

extension ContinuousClock: AutoRoutingClock {}
