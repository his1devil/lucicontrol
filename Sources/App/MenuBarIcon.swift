import AppKit

/// The menu bar glyph (design round 14b): a rounded screen, its left half filled with two
/// dots, two lines on the right, one long and one short. Four states: dimmed when nothing
/// is shared, plain when sharing, an orange dot for a waiting approval, a blue dot for an
/// update.
enum MenuBarIcon {
  enum State: Equatable {
    case off
    case sharing
    case waiting
    case update
  }

  static let size = NSSize(width: 23, height: 18)

  /// Drawn on demand in the menu bar's own appearance, so the glyph takes the label colour
  /// there and the dot keeps its colour (a template image would tint the dot too).
  static func image(for state: State) -> NSImage {
    let image = NSImage(size: size, flipped: true) { _ in
      draw(state: state)
      return true
    }
    image.isTemplate = false
    image.accessibilityDescription = "LuciControl"
    return image
  }

  private static func draw(state: State) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let scale: CGFloat = 0.86 // the 24-unit canvas at about 20.6 pt (the user asked for a touch bigger than the design's 18)
    ctx.saveGState()
    ctx.setAlpha(state == .off ? 0.4 : 1)
    ctx.translateBy(x: 0, y: 0)
    ctx.scaleBy(x: scale, y: scale)
    let ink = NSColor.labelColor
    ink.setStroke()
    ink.setFill()
    let lineWidth: CGFloat = 1.6

    // Outer screen.
    let outer = NSBezierPath(roundedRect: NSRect(x: 2.2, y: 5.2, width: 19.6, height: 13.6), xRadius: 3.4, yRadius: 3.4)
    outer.lineWidth = lineWidth
    outer.stroke()

    // Left half, filled, with two holes.
    let half = NSBezierPath()
    half.move(to: NSPoint(x: 5.6, y: 5.2))
    half.line(to: NSPoint(x: 12, y: 5.2))
    half.line(to: NSPoint(x: 12, y: 18.8))
    half.line(to: NSPoint(x: 5.6, y: 18.8))
    half.appendArc(withCenter: NSPoint(x: 5.6, y: 15.4), radius: 3.4, startAngle: 90, endAngle: 180, clockwise: false)
    half.line(to: NSPoint(x: 2.2, y: 8.6))
    half.appendArc(withCenter: NSPoint(x: 5.6, y: 8.6), radius: 3.4, startAngle: 180, endAngle: 270, clockwise: false)
    half.close()
    half.lineWidth = lineWidth
    half.lineJoinStyle = .round
    half.stroke()
    let filled = NSBezierPath()
    filled.append(half)
    filled.appendOval(in: NSRect(x: 4.2, y: 7.4, width: 2, height: 2))
    filled.appendOval(in: NSRect(x: 6.8, y: 7.4, width: 2, height: 2))
    filled.windingRule = .evenOdd
    filled.fill()

    // The two lines on the right.
    let lines = NSBezierPath()
    lines.lineWidth = lineWidth
    lines.lineCapStyle = .round
    lines.move(to: NSPoint(x: 14.6, y: 10.6))
    lines.line(to: NSPoint(x: 19.2, y: 10.6))
    lines.move(to: NSPoint(x: 14.6, y: 13.4))
    lines.line(to: NSPoint(x: 17.4, y: 13.4))
    lines.stroke()
    ctx.restoreGState()

    // The badge: a hole punched around it keeps it apart from the glyph.
    let dotColor: NSColor? = switch state {
    case .waiting: NSColor(hex: "#ff9f0a")
    case .update: NSColor(hex: "#0a84ff")
    default: nil
    }
    if let dotColor {
      let center = NSPoint(x: 20, y: 3.5)
      ctx.saveGState()
      ctx.setBlendMode(.destinationOut)
      NSColor.black.setFill()
      NSBezierPath(ovalIn: NSRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)).fill()
      ctx.restoreGState()
      dotColor.setFill()
      NSBezierPath(ovalIn: NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)).fill()
    }
  }
}
