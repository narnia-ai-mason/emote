import Foundation

public struct AutoRoutingSnapshot: Equatable, Sendable {
  public var lastBackend: String
  public var lastAppleMilliseconds: Int?
  public var skippedForSlowness: Bool

  public init(
    lastBackend: String = "",
    lastAppleMilliseconds: Int? = nil,
    skippedForSlowness: Bool = false
  ) {
    self.lastBackend = lastBackend
    self.lastAppleMilliseconds = lastAppleMilliseconds
    self.skippedForSlowness = skippedForSlowness
  }

  public var summary: String? {
    var parts: [String] = []
    if !lastBackend.isEmpty {
      parts.append("Last used \(lastBackend).")
    }
    if let lastAppleMilliseconds {
      parts.append("On-device took \(lastAppleMilliseconds) ms.")
    }
    if skippedForSlowness {
      parts.append("Auto is using OpenRouter because on-device was too slow.")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }
}

public final class AutoRoutingMemory: @unchecked Sendable {
  public static let shared = AutoRoutingMemory()

  private let defaults: UserDefaults
  private let lock = NSLock()

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var snapshot: AutoRoutingSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let milliseconds = defaults.object(forKey: Keys.lastAppleMilliseconds) as? Int
    return AutoRoutingSnapshot(
      lastBackend: defaults.string(forKey: Keys.lastBackend) ?? "",
      lastAppleMilliseconds: milliseconds,
      skippedForSlowness: defaults.bool(forKey: Keys.skippedForSlowness)
    )
  }

  public var shouldTryOnDevice: Bool {
    !snapshot.skippedForSlowness
  }

  public func recordOnDeviceSuccess(duration: Duration, threshold: Duration) {
    let milliseconds = duration.milliseconds
    lock.lock()
    defaults.set("on-device", forKey: Keys.lastBackend)
    defaults.set(milliseconds, forKey: Keys.lastAppleMilliseconds)
    defaults.set(duration > threshold, forKey: Keys.skippedForSlowness)
    lock.unlock()
  }

  public func recordOnDeviceFailure() {
    lock.lock()
    defaults.set("on-device", forKey: Keys.lastBackend)
    lock.unlock()
  }

  public func recordOpenRouter() {
    lock.lock()
    defaults.set("OpenRouter", forKey: Keys.lastBackend)
    lock.unlock()
  }

  public func resetSkip() {
    lock.lock()
    defaults.set(false, forKey: Keys.skippedForSlowness)
    lock.unlock()
  }

  private enum Keys {
    static let lastBackend = "emote.auto.lastBackend"
    static let lastAppleMilliseconds = "emote.auto.lastAppleMilliseconds"
    static let skippedForSlowness = "emote.auto.skippedForSlowness"
  }
}
