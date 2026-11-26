import EmoteCore
import XCTest

final class EmojiDistributionSamplerTests: XCTestCase {
  private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return state
    }
  }

  private func rec(_ emoji: String) -> EmojiRecommendation {
    EmojiRecommendation(emoji: emoji, description: emoji)
  }

  func testNormalizeSumsToOneAndMergesSurfaceVariants() {
    let dist = EmojiDistributionSampler.normalize(entries: [
      (rec("❤️"), [10.0, 10.0]),
      (rec("😊"), [10.0]),
    ])
    XCTAssertEqual(dist.count, 2)
    XCTAssertEqual(dist[0].recommendation.emoji, "❤️")
    XCTAssertEqual(dist[0].probability, 2.0 / 3.0, accuracy: 1e-9)
    XCTAssertEqual(dist[1].probability, 1.0 / 3.0, accuracy: 1e-9)
    XCTAssertEqual(dist.reduce(0) { $0 + $1.probability }, 1.0, accuracy: 1e-9)
  }

  func testThresholdDropsLowProbabilityTailNoise() {
    let dist = [
      ScoredEmoji(recommendation: rec("☕"), probability: 0.9949),
      ScoredEmoji(recommendation: rec("😌"), probability: 0.0049),
      ScoredEmoji(recommendation: rec("📄"), probability: 0.0002),
    ]
    var rng = SeededRNG(state: 42)
    let picked = EmojiDistributionSampler.sample(
      from: dist,
      minProbability: 0.005,
      using: &rng
    )
    XCTAssertEqual(picked.map(\.emoji), ["☕"])
  }

  func testRepeatedSamplingNeverFallsBelowThreshold() {
    let dist = [
      ScoredEmoji(recommendation: rec("👋"), probability: 0.60),
      ScoredEmoji(recommendation: rec("🙋"), probability: 0.30),
      ScoredEmoji(recommendation: rec("🙂"), probability: 0.095),
      ScoredEmoji(recommendation: rec("🌎"), probability: 0.004),
      ScoredEmoji(recommendation: rec("➕"), probability: 0.001),
    ]
    let valid = Set(["👋", "🙋", "🙂"])
    var rng = SeededRNG(state: 7)
    for _ in 0..<50 {
      let picked = EmojiDistributionSampler.sample(
        from: dist,
        minProbability: 0.005,
        using: &rng
      )
      XCTAssertEqual(picked.count, 3)
      XCTAssertTrue(Set(picked.map(\.emoji)).isSubset(of: valid))
    }
  }

  func testFreshFlatDistributionNeverReturnsEmpty() {
    let dist = [
      ScoredEmoji(recommendation: rec("✨"), probability: 0.003),
      ScoredEmoji(recommendation: rec("🎉"), probability: 0.002),
    ]
    var rng = SeededRNG(state: 1)
    let picked = EmojiDistributionSampler.sample(
      from: dist,
      minProbability: 0.005,
      using: &rng
    )
    XCTAssertEqual(picked.map(\.emoji), ["✨"])
  }

  func testGumbelTopKSamplesWithoutDuplicatesAndRespectsWeights() {
    let dist = [
      ScoredEmoji(recommendation: rec("🥳"), probability: 0.70),
      ScoredEmoji(recommendation: rec("🎉"), probability: 0.20),
      ScoredEmoji(recommendation: rec("💃"), probability: 0.06),
      ScoredEmoji(recommendation: rec("🍾"), probability: 0.04),
    ]
    var rng = SeededRNG(state: 12345)
    var partyFirst = 0
    var seenOrders = Set<[String]>()
    for _ in 0..<200 {
      let picked = EmojiDistributionSampler.sample(
        from: dist,
        minProbability: 0.005,
        maxCount: 3,
        using: &rng
      ).map(\.emoji)
      XCTAssertEqual(picked.count, 3)
      XCTAssertEqual(Set(picked).count, 3)
      if picked.first == "🥳" { partyFirst += 1 }
      seenOrders.insert(picked)
    }
    XCTAssertGreaterThan(partyFirst, 100)
    XCTAssertGreaterThan(seenOrders.count, 3)
  }
}
