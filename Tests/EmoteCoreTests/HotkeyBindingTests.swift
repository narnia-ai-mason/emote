import Carbon.HIToolbox
import EmoteCore
import XCTest

final class HotkeyBindingTests: XCTestCase {
  func testDefaultIsControlCommandE() {
    XCTAssertEqual(HotkeyBinding.default.keyCode, UInt16(kVK_ANSI_E))
    XCTAssertEqual(HotkeyBinding.default.modifiers, [.control, .command])
    XCTAssertTrue(HotkeyBinding.default.hasRequiredModifiers)
    XCTAssertEqual(HotkeyBinding.default.carbonModifiers, UInt32(cmdKey | controlKey))
    XCTAssertTrue(HotkeyBinding.default.displayName.hasPrefix("⌃"))
    XCTAssertTrue(HotkeyBinding.default.displayName.contains("⌘"))
    XCTAssertTrue(HotkeyBinding.default.displayName.hasSuffix("E"))
  }

  func testShiftAloneIsNotEnoughForAGlobalHotkey() {
    let binding = HotkeyBinding(keyCode: UInt16(kVK_ANSI_E), modifiers: [.shift])
    XCTAssertFalse(binding.hasRequiredModifiers)
  }

  func testFunctionModifierIsEnoughAndNeedsAnEventTap() {
    let withKey = HotkeyBinding(keyCode: UInt16(kVK_ANSI_E), modifiers: [.function])
    XCTAssertTrue(withKey.hasRequiredModifiers)
    XCTAssertTrue(withKey.usesEventTap)
    XCTAssertEqual(withKey.displayName, "fnE")
    XCTAssertEqual(withKey.carbonModifiers, 0)

    let globe = HotkeyBinding(keyCode: UInt16(kVK_Function), modifiers: [.function])
    XCTAssertTrue(globe.isFunctionKeyOnly)
    XCTAssertEqual(globe.displayName, "fn")
  }

  func testRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(HotkeyBinding.default)
    let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
    XCTAssertEqual(decoded, .default)
  }
}
