import AppKit

// Adapted from yptd-desktop's 600 × 380 smile layout. Finder supplies the
// two icons at (150,150)/(450,150); the background only supplies copy and mouth.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for scale in [1, 2] {
  let width = 600 * scale, height = 380 * scale
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  bitmap.size = NSSize(width: 600, height: 380)
  NSGraphicsContext.saveGraphicsState()
  let context = NSGraphicsContext(bitmapImageRep: bitmap)!
  NSGraphicsContext.current = context
  let cg = context.cgContext
  // NSGraphicsContext already uses bitmap.size to establish the Retina scale.
  cg.translateBy(x: 0, y: 380)
  cg.scaleBy(x: 1, y: -1)
  NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: 600, height: 380).fill()

  func centered(_ text: String, y: CGFloat, size: CGFloat, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 28, y: y, width: 544, height: 26), withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: .regular),
      .foregroundColor: color, .paragraphStyle: paragraph
    ])
  }
  centered("将 LuciControl 拖到 Applications，完成安装", y: 40, size: 15,
    color: NSColor(srgbRed: 0.28, green: 0.30, blue: 0.36, alpha: 1))
  centered("Drag LuciControl to Applications to install", y: 66, size: 12,
    color: NSColor(srgbRed: 0.55, green: 0.57, blue: 0.63, alpha: 1))

  let ink = NSColor(srgbRed: 0x7D / 255.0, green: 0x87 / 255.0, blue: 0xF5 / 255.0, alpha: 1)
  ink.setStroke()
  let curve = NSBezierPath()
  curve.lineWidth = 3.6
  curve.lineCapStyle = .round
  curve.lineJoinStyle = .round
  curve.move(to: NSPoint(x: 175, y: 262))
  curve.curve(to: NSPoint(x: 425, y: 254), controlPoint1: NSPoint(x: 240, y: 312), controlPoint2: NSPoint(x: 360, y: 314))
  let angle = atan2(-60.0, 65.0)
  for side in [-1.0, 1.0] {
    let a = angle + .pi + side * 26 * .pi / 180
    curve.move(to: NSPoint(x: 425, y: 254))
    curve.line(to: NSPoint(x: 425 + cos(a) * 17, y: 254 + sin(a) * 17))
  }
  curve.stroke()
  NSGraphicsContext.restoreGraphicsState()
  let name = scale == 1 ? "background.png" : "background@2x.png"
  try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
