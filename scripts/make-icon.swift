import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
  let background = NSBezierPath(roundedRect: rect.insetBy(dx: 64, dy: 64), xRadius: 220, yRadius: 220)
  NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).setFill()
  background.fill()

  let emoji = "🙂" as NSString
  let font = NSFont.systemFont(ofSize: 560)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
  ]
  let textSize = emoji.size(withAttributes: attributes)
  let origin = NSPoint(
    x: rect.midX - textSize.width / 2,
    y: rect.midY - textSize.height / 2 - 20
  )
  emoji.draw(at: origin, withAttributes: attributes)
  return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
  fatalError("Could not render icon")
}
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Could not encode PNG")
}

let pngURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: pngURL)
