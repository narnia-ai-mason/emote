import EmoteCore
import XCTest

final class EngineRequirementsTests: XCTestCase {
  func testAutoNeedsAppleIntelligenceOrAnAPIKey() {
    XCTAssertThrowsError(
      try EngineRequirements.validate(
        engine: .auto,
        apiKey: "",
        onDevice: .appleIntelligenceNotEnabled
      )
    ) { error in
      XCTAssertEqual(
        error as? EmojiRecommendationError,
        .notConfigured("Turn on Apple Intelligence or add an OpenRouter API key.")
      )
    }

    XCTAssertNoThrow(
      try EngineRequirements.validate(
        engine: .auto,
        apiKey: "sk-test",
        onDevice: .appleIntelligenceNotEnabled
      )
    )
    XCTAssertNoThrow(
      try EngineRequirements.validate(
        engine: .auto,
        apiKey: "",
        onDevice: .available
      )
    )
  }

  func testOnDeviceIgnoresTheAPIKey() {
    XCTAssertNoThrow(
      try EngineRequirements.validate(
        engine: .onDevice,
        apiKey: "",
        onDevice: .available
      )
    )
    XCTAssertThrowsError(
      try EngineRequirements.validate(
        engine: .onDevice,
        apiKey: "sk-test",
        onDevice: .appleIntelligenceNotEnabled
      )
    ) { error in
      XCTAssertEqual(
        error as? EmojiRecommendationError,
        .onDeviceUnavailable(OnDeviceModelStatus.appleIntelligenceNotEnabled.summary)
      )
    }
  }

  func testOpenRouterRequiresAKeyAndIgnoresAppleIntelligence() {
    XCTAssertNoThrow(
      try EngineRequirements.validate(
        engine: .openRouter,
        apiKey: "sk-test",
        onDevice: .unsupportedOS
      )
    )
    XCTAssertThrowsError(
      try EngineRequirements.validate(
        engine: .openRouter,
        apiKey: "  ",
        onDevice: .available
      )
    ) { error in
      XCTAssertEqual(error as? EmojiRecommendationError, .missingAPIKey)
    }
  }

  func testOnDeviceFallsBackToAutoWhenUnavailable() {
    XCTAssertEqual(
      RecommendationEngine.onDevice.resolved(onDevice: .available),
      .onDevice
    )
    XCTAssertEqual(
      RecommendationEngine.onDevice.resolved(onDevice: .appleIntelligenceNotEnabled),
      .auto
    )
    XCTAssertEqual(
      RecommendationEngine.onDevice.resolved(onDevice: .unsupportedOS),
      .auto
    )
    XCTAssertEqual(
      RecommendationEngine.openRouter.resolved(onDevice: .deviceNotEligible),
      .openRouter
    )
  }
}
