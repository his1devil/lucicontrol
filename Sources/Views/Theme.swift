import AppKit
import SwiftUI

/// The design canvas's colours and measurements (PLAN.md appendix). Every colour is a
/// dynamic NSColor, so the same views draw the light (9a) and dark (9b) options.
enum DS {
  // Text
  static let ink = dyn(light: "#1d1d1f", dark: "#f5f5f7")
  static let ink2 = dyn(light: "#6e6e73", dark: "#98989d")
  static let ink3 = dyn(light: "#8e8e93", dark: "#8e8e93")
  /// Titles and section names of sessions that are not shared.
  static let inkOff = dyn(light: "#9a9a9a", dark: "#6a6a6e")
  static let sectionOff = dyn(light: "#b0b0b5", dark: "#6a6a6e")
  static let waitingText = dyn(light: "#e07b00", dark: "#ff9f0a")

  // Accent
  static let accent = dyn(light: "#0a84ff", dark: "#0a84ff")
  static let accentText = dyn(light: "#0a84ff", dark: "#4aa3ff")
  static let accentFill = dynA(light: ("#0a84ff", 0.10), dark: ("#0a84ff", 0.18))
  static let accentFillStrong = dynA(light: ("#0a84ff", 0.08), dark: ("#0a84ff", 0.16))

  // Surfaces
  static let panel = dynA(light: ("#fafafc", 0.80), dark: ("#242426", 0.82))
  static let fill = dynA(light: ("#000000", 0.04), dark: ("#ffffff", 0.07))
  static let fill2 = dynA(light: ("#000000", 0.05), dark: ("#ffffff", 0.08))
  static let fill3 = dynA(light: ("#000000", 0.08), dark: ("#ffffff", 0.14))
  static let line = dynA(light: ("#000000", 0.08), dark: ("#ffffff", 0.08))
  static let segment = dynA(light: ("#000000", 0.06), dark: ("#ffffff", 0.08))
  static let segmentOn = dyn(light: "#ffffff", dark: "#48484a")
  static let checkOff = dynA(light: ("#000000", 0.25), dark: ("#ffffff", 0.30))
  static let qrBackground = dyn(light: "#ffffff", dark: "#ffffff")
  static let progressTrack = dynA(light: ("#000000", 0.06), dark: ("#ffffff", 0.10))
  static let progressFill = dyn(light: "#1d1d1f", dark: "#f5f5f7")

  // Status colours
  static let waiting = dyn(light: "#f5871f", dark: "#f5871f")
  static let running = dyn(light: "#34c759", dark: "#34c759")
  static let idle = dyn(light: "#9a9a9a", dark: "#9a9a9a")
  static let barOff = dynA(light: ("#000000", 0.14), dark: ("#ffffff", 0.16))
  static let online = dyn(light: "#34c759", dark: "#30d158")
  static let offline = dyn(light: "#c4c4c4", dark: "#5a5a5e")
  static let pausedDot = dyn(light: "#8e8e93", dark: "#8e8e93")
  static let badgeWaiting = dyn(light: "#ff9f0a", dark: "#ff9f0a")
  static let badgeUpdate = dyn(light: "#0a84ff", dark: "#0a84ff")

  // Pill toggle
  static let toggleOn = dyn(light: "#0a84ff", dark: "#0a84ff")
  static let toggleOff = dyn(light: "#e8eaee", dark: "#2c2c2e")
  static let toggleOffText = dyn(light: "#8e8e93", dark: "#8e8e93")
  static let knobOn = dyn(light: "#ffffff", dark: "#ffffff")
  static let knobOff = dyn(light: "#ffffff", dark: "#636366")

  // Measurements
  static let panelWidth: CGFloat = 412
  /// The design's 590 raised by half (the user's call); a small screen caps it further.
  static let panelMaxHeight: CGFloat = 885
  static let panelRadius: CGFloat = 14
  static let side: CGFloat = 20

  static func dyn(light: String, dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      appearance.isDark ? NSColor(hex: dark) : NSColor(hex: light)
    })
  }

  static func dynA(light: (String, CGFloat), dark: (String, CGFloat)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      appearance.isDark ? NSColor(hex: dark.0).withAlphaComponent(dark.1) : NSColor(hex: light.0).withAlphaComponent(light.1)
    })
  }
}

extension NSAppearance {
  var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
  /// "#rrggbb" in sRGB.
  convenience init(hex: String) {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}

extension Font {
  /// The canvas's `-apple-system` sizes, in points.
  static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }

  static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}
