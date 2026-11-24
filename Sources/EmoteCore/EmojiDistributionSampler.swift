import Foundation

public struct ScoredEmoji: Equatable, Sendable {
  public let recommendation: EmojiRecommendation
  public let probability: Double

  public init(recommendation: EmojiRecommendation, probability: Double) {
    self.recommendation = recommendation
    self.probability = probability
  }
}

public enum EmojiDistributionSampler {
  public static let defaultMinProbability = 0.005
  public static let defaultRelaxedProbabilities = [0.0005, 0.00005]
  public static let defaultMaxCount = 10
  public static let defaultTemperature = 1.0

  /// Normalizes logits restricted strictly to emoji tokens so non-emoji vocab leakage cannot skew scores.
  /// Multiple surface tokens for the same emoji (e.g. FE0F or leading-space variants) are summed in probability space.
  public static func normalize(
    entries: [(recommendation: EmojiRecommendation, logits: [Float])]
  ) -> [ScoredEmoji] {
    var maxLogit = -Double.infinity
    for entry in entries {
      for logit in entry.logits {
        let value = Double(logit)
        if value.isFinite, value > maxLogit {
          maxLogit = value
        }
      }
    }
    guard maxLogit.isFinite else { return [] }

    var weights: [(EmojiRecommendation, Double)] = []
    weights.reserveCapacity(entries.count)
    var total = 0.0
    for entry in entries {
      var sum = 0.0
      for logit in entry.logits {
        let value = Double(logit)
        if value.isFinite {
          sum += exp(value - maxLogit)
        }
      }
      if sum > 0 {
        weights.append((entry.recommendation, sum))
        total += sum
      }
    }
    guard total > 0 else { return [] }

    return weights
      .map { ScoredEmoji(recommendation: $0.0, probability: $0.1 / total) }
      .sorted { $0.probability > $1.probability }
  }

  /// Samples without replacement (Gumbel-Top-k) from candidates clearing the probability threshold.
  /// When repeating on the same situation with `excluding`, relaxes the threshold if the primary pool is exhausted.
  public static func sample<RNG: RandomNumberGenerator>(
    from distribution: [ScoredEmoji],
    excluding: Set<String> = [],
    minProbability: Double = defaultMinProbability,
    relaxedProbabilities: [Double] = defaultRelaxedProbabilities,
    maxCount: Int = defaultMaxCount,
    temperature: Double = defaultTemperature,
    using rng: inout RNG
  ) -> [EmojiRecommendation] {
    guard !distribution.isEmpty, maxCount > 0 else { return [] }
    let effectiveTemp = max(temperature, 1e-4)

    let remaining = excluding.isEmpty
      ? distribution
      : distribution.filter { !excluding.contains($0.recommendation.emoji) }

    var pool = remaining.filter { $0.probability >= minProbability }
    if pool.isEmpty, !excluding.isEmpty {
      for cutoff in relaxedProbabilities {
        pool = remaining.filter { $0.probability >= cutoff }
        if !pool.isEmpty { break }
      }
      if pool.isEmpty, !remaining.isEmpty {
        pool = Array(remaining.prefix(maxCount))
      }
    }
    if pool.isEmpty {
      if let top = remaining.first ?? distribution.first {
        pool = [top]
      } else {
        return []
      }
    }

    // Gumbel-Top-k is mathematically equivalent to sequential categorical sampling without replacement.
    let keyed = pool.map { item -> (EmojiRecommendation, Double) in
      let raw = Double.random(in: 0..<1, using: &rng)
      let u = min(max(raw, 1e-12), 1.0 - 1e-12)
      let gumbel = -log(-log(u))
      let score = log(max(item.probability, 1e-15)) / effectiveTemp + gumbel
      return (item.recommendation, score)
    }

    return keyed
      .sorted { $0.1 > $1.1 }
      .prefix(maxCount)
      .map(\.0)
  }

  public static func sample(
    from distribution: [ScoredEmoji],
    excluding: Set<String> = [],
    minProbability: Double = defaultMinProbability,
    relaxedProbabilities: [Double] = defaultRelaxedProbabilities,
    maxCount: Int = defaultMaxCount,
    temperature: Double = defaultTemperature
  ) -> [EmojiRecommendation] {
    var rng = SystemRandomNumberGenerator()
    return sample(
      from: distribution,
      excluding: excluding,
      minProbability: minProbability,
      relaxedProbabilities: relaxedProbabilities,
      maxCount: maxCount,
      temperature: temperature,
      using: &rng
    )
  }
}
