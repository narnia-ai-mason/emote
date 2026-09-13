public enum OnDeviceModelStatus: Equatable, Sendable {
  case available
  case unsupportedOS
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case unavailable(String)

  public var isAvailable: Bool {
    self == .available
  }

  public var canOpenSystemSettings: Bool {
    switch self {
    case .appleIntelligenceNotEnabled, .modelNotReady:
      true
    default:
      false
    }
  }

  public var summary: String {
    switch self {
    case .available:
      "On-device Apple Intelligence is ready."
    case .unsupportedOS:
      "On-device needs macOS 26 or later."
    case .deviceNotEligible:
      "This Mac doesn't support Apple Intelligence."
    case .appleIntelligenceNotEnabled:
      "Turn on Apple Intelligence in System Settings."
    case .modelNotReady:
      "The on-device model is still downloading."
    case .unavailable(let detail):
      detail
    }
  }

  public static var current: OnDeviceModelStatus {
    AppleFoundationAvailability.current
  }
}

enum AppleFoundationAvailability {
  static var current: OnDeviceModelStatus {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return AppleFoundationEmojiRecommender.status()
      }
    #endif
    return .unsupportedOS
  }
}
