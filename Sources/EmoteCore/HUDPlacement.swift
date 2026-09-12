import CoreGraphics
import Foundation

public enum HUDPlacement: Sendable {
  public static func origin(
    size: CGSize,
    anchor: CGRect?,
    visible: CGRect
  ) -> CGPoint {
    let box: CGRect
    if let anchor, anchor.width > 0 || anchor.height > 0 {
      box = anchor
    } else {
      box = CGRect(x: visible.midX, y: visible.midY + 40, width: 2, height: 16)
    }

    let minX = visible.minX + 8
    let maxX = visible.maxX - size.width - 8
    let x = min(max(box.minX, minX), max(minX, maxX))
    let gap: CGFloat = 6
    let below = box.minY - size.height - gap
    if below >= visible.minY + 8 {
      return CGPoint(x: x, y: below)
    }

    let above = box.maxY + gap
    if above + size.height <= visible.maxY - 8 {
      return CGPoint(x: x, y: above)
    }

    return CGPoint(
      x: x,
      y: min(max(below, visible.minY + 8), visible.maxY - size.height - 8)
    )
  }

  public static func cocoaRect(fromAX rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
    CGRect(
      x: rect.origin.x,
      y: primaryMaxY - rect.origin.y - rect.height,
      width: rect.width,
      height: rect.height
    )
  }
}
