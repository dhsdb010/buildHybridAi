import SwiftUI
import UIKit

/// MTA design tokens (see DESIGN.md). Every semantic color has a Night (dark) and Day (light) value;
/// status colors are the same in both. Mirrors the Figma "MTA Color" variable collection.
enum MTA {
  private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
  }
  private static func fixed(_ hex: UInt32) -> Color { Color(UIColor(hex: hex)) }

  // Surfaces & text
  static let surface = dyn(0x000000, 0xFFFFFF)
  static let raised = dyn(0x3B3B3B, 0xF5F5F5)
  static let inverse = dyn(0xF5F5F5, 0x000000)
  static let text = dyn(0xFFFFFF, 0x000000)
  static let text2 = dyn(0x969696, 0x3B3B3B)
  static let textInverse = dyn(0x000000, 0xFFFFFF)
  static let border = dyn(0xFFFFFF, 0x000000)
  static let subtle = dyn(0x3B3B3B, 0x969696)

  // Accent & status (never change between modes)
  static let accent = fixed(0x0050EA)
  static let onTrack = fixed(0x139240)
  static let urgent = fixed(0xFF0000)
  static let obstacle = fixed(0xFF6B00)
  static let notice = fixed(0xFFD51F)
  static let assistance = fixed(0x8A05B9)
  /// Glyphs/labels on blue, green, red, purple fills.
  static let onColor = Color.white
  /// Glyphs/labels on yellow and orange fills.
  static let onNotice = Color.black

  // 4-column grid: 30 margin · 15 gutter (MTA mobile).
  static let margin: CGFloat = 30
  static let gutter: CGFloat = 15
}

extension UIColor {
  convenience init(hex: UInt32) {
    self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
              blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}

// MARK: - Type scale (Helvetica Neue, tracking −1%, Label uppercase +8%)

enum MTAType {
  case displayLarge, displayMedium, headline, subheadMedium, button1, subheadNormal, body1, button2, body2, label, tab

  var spec: (size: CGFloat, weight: String, relative: Font.TextStyle) {
    switch self {
    case .displayLarge: (48, "Bold", .largeTitle)
    case .displayMedium: (30, "Bold", .title)
    case .headline: (26, "Bold", .title2)
    case .subheadMedium: (24, "Medium", .title3)
    case .button1: (20, "Medium", .headline)
    case .subheadNormal: (18, "Medium", .headline)
    case .body1: (18, "", .body)
    case .button2: (16, "Medium", .callout)
    case .body2: (14, "", .subheadline)
    case .label: (11, "Bold", .caption2)
    case .tab: (11, "Medium", .caption2)
    }
  }

  var font: Font {
    let s = spec
    return .custom(s.weight.isEmpty ? "HelveticaNeue" : "HelveticaNeue-\(s.weight)", size: s.size, relativeTo: s.relative)
  }
}

extension View {
  /// Applies an MTA text style: font, tracking and (for Label) uppercase.
  func mta(_ type: MTAType) -> some View {
    font(type.font)
      .tracking(type == .label ? type.spec.size * 0.08 : type.spec.size * -0.01)
      .textCase(type == .label ? .uppercase : nil)
  }
}

// MARK: - Clock (debug override for demos: `-now 2026-12-03T16:30`)

enum AppClock {
  static var now: Date {
    #if DEBUG
      if let s = UserDefaults.standard.string(forKey: "now"), let d = debugFormatter.date(from: s) { return d }
    #endif
    return Date()
  }

  private static let debugFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
  }()
}
