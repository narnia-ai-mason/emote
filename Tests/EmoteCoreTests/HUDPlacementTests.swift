import EmoteCore
import XCTest

final class HUDPlacementTests: XCTestCase {
  func testSitsBelowAndLeftAlignedToTheCaret() {
    let origin = HUDPlacement.origin(
      size: CGSize(width: 220, height: 52),
      anchor: CGRect(x: 120, y: 400, width: 48, height: 18),
      visible: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(origin.x, 120)
    XCTAssertEqual(origin.y, 400 - 52 - 6)
  }

  func testFlipsAboveWhenThereIsNoRoomBelow() {
    let origin = HUDPlacement.origin(
      size: CGSize(width: 220, height: 52),
      anchor: CGRect(x: 40, y: 20, width: 12, height: 16),
      visible: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(origin.x, 40)
    XCTAssertEqual(origin.y, 20 + 16 + 6)
  }

  func testCentersWhenTheCaretIsMissing() {
    let origin = HUDPlacement.origin(
      size: CGSize(width: 220, height: 52),
      anchor: nil,
      visible: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(origin.x, 400)
    XCTAssertEqual(origin.y, 340 - 52 - 6)
  }

  func testConvertsTopLeftAccessibilityFramesToCocoa() {
    let cocoa = HUDPlacement.cocoaRect(
      fromAX: CGRect(x: 100, y: 40, width: 12, height: 16),
      primaryMaxY: 982
    )

    XCTAssertEqual(cocoa, CGRect(x: 100, y: 982 - 40 - 16, width: 12, height: 16))
  }
}
