import SwiftUI

/// Status → color. Color always means status (DESIGN.md).
enum MTAStatus {
  case onTrack, urgent, obstacle, notice, accent, assistance

  var color: Color {
    switch self {
    case .onTrack: MTA.onTrack
    case .urgent: MTA.urgent
    case .obstacle: MTA.obstacle
    case .notice: MTA.notice
    case .accent: MTA.accent
    case .assistance: MTA.assistance
    }
  }

  /// Glyph/label color on top of this fill.
  var foreground: Color { self == .notice || self == .obstacle ? MTA.onNotice : MTA.onColor }
}

// MARK: - Text helpers

struct MTALabel: View {
  let text: String
  var color: Color = MTA.text2
  init(_ text: String, color: Color = MTA.text2) { self.text = text; self.color = color }
  var body: some View { Text(text).mta(.label).foregroundStyle(color) }
}

// MARK: - Number box (78×78 → one per grid column)

struct NumberBox: View {
  enum Style { case outline, filled, status(MTAStatus) }
  let value: String
  let caption: String
  var style: Style = .outline

  var body: some View {
    VStack(alignment: .leading) {
      Text(value).mta(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
      Spacer(minLength: 0)
      Text(caption).mta(.label).lineLimit(1).minimumScaleFactor(0.7)
    }
    .foregroundStyle(foreground)
    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
    .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .leading)
    .background(background, in: .rect(cornerRadius: 12))
    .overlay { if case .outline = style { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) } }
    .accessibilityElement(children: .combine)
  }

  private var foreground: Color {
    switch style { case .outline: MTA.text; case .filled: MTA.textInverse; case let .status(s): s.foreground }
  }
  private var background: Color {
    switch style { case .outline: .clear; case .filled: MTA.inverse; case let .status(s): s.color }
  }
}

/// Four equal columns with the 15pt gutter.
struct GridRow4<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View { HStack(spacing: MTA.gutter) { content } }
}

// MARK: - Milestone / calendar circle

struct Milestone: View {
  enum State { case done, today, upcoming, missed, deadline, off, header }
  let value: String
  var state: State
  var size: CGFloat = 40

  var body: some View {
    Text(value)
      .mta(.button2).monospacedDigit()
      .foregroundStyle(foreground)
      .frame(width: size, height: size)
      .background(fill, in: .circle)
      .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: state == .upcoming ? 1.5 : 2) } }
  }

  private var foreground: Color {
    switch state {
    case .done, .deadline: MTA.onColor
    case .today: MTA.accent
    case .missed: MTA.obstacle
    case .upcoming: MTA.text
    case .off: MTA.text2
    case .header: MTA.textInverse
    }
  }
  private var fill: Color {
    switch state {
    case .done: MTA.onTrack
    case .deadline: MTA.urgent
    case .off: MTA.raised
    case .header: MTA.inverse
    default: .clear
    }
  }
  private var ring: Color? {
    switch state { case .today: MTA.accent; case .upcoming: MTA.border; case .missed: MTA.obstacle; default: nil }
  }
}

/// Milestone with an SF Symbol inside (readiness checks).
struct MilestoneSymbol: View {
  let systemName: String
  let ok: Bool
  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(ok ? MTA.onColor : MTA.obstacle)
      .frame(width: 40, height: 40)
      .background(ok ? MTA.onTrack : .clear, in: .circle)
      .overlay { if !ok { Circle().strokeBorder(MTA.obstacle, lineWidth: 2) } }
  }
}

// MARK: - Trip bullet (subway-style: glyph = item, fill = status)

struct TripBullet: View {
  let systemName: String
  var status: MTAStatus = .accent
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(status.foreground)
      .frame(width: size, height: size)
      .background(status.color, in: .circle)
  }
}

// MARK: - Cards

struct NoticeCard: View {
  let text: String
  var body: some View {
    Text(text).mta(.body2).foregroundStyle(MTA.onNotice)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(MTA.notice, in: .rect(cornerRadius: 12))
  }
}

struct FeatureCard: View {
  let label: String
  let title: String
  let detail: String
  let systemImage: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(label).mta(.label)
          Text(title).mta(.headline)
          Text(detail).mta(.body2).opacity(0.7).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(MTA.onColor)
          .frame(width: 44, height: 44)
          .background(MTA.accent, in: .circle)
      }
      .foregroundStyle(MTA.textInverse)
      .padding(.horizontal, 15).padding(.vertical, 18)
      .background(MTA.inverse, in: .rect(cornerRadius: 20))
    }
    .buttonStyle(.plain)
  }
}

/// 2pt outline card (MTA kiosk card).
struct OutlineCard<Content: View>: View {
  var stroke: Color = MTA.border
  var lineWidth: CGFloat = 2
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 10) { content }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: lineWidth) }
  }
}

/// "LABEL      value" row inside cards.
struct FieldRow: View {
  let label: String
  let value: String
  var highlight: MTAStatus?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(label).mta(.label).foregroundStyle(MTA.text2).frame(width: 92, alignment: .leading)
      Text(value).mta(.subheadNormal).foregroundStyle(MTA.text).textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .padding(.vertical, highlight == nil ? 0 : 4)
    .padding(.leading, highlight == nil ? 0 : 10)
    .background {
      if let highlight {
        HStack(spacing: 0) { Rectangle().fill(highlight.color).frame(width: 4); MTA.raised }
          .clipShape(.rect(cornerRadius: 4))
      }
    }
  }
}

// MARK: - Buttons (full-width pill)

struct MTAButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, dark }
  var kind: Kind = .primary
  var height: CGFloat = 52
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .mta(.button1)
      .frame(maxWidth: .infinity, minHeight: height)
      .foregroundStyle(fg)
      .background(bg(pressed: configuration.isPressed), in: .capsule)
      .overlay { if kind == .secondary { Capsule().strokeBorder(MTA.border, lineWidth: 2) } }
      .opacity(enabled ? 1 : 0.4)
      .contentShape(.capsule)
  }
  private var fg: Color { switch kind { case .primary: MTA.onColor; case .secondary: MTA.text; case .dark: MTA.textInverse } }
  private func bg(pressed: Bool) -> Color {
    switch kind {
    case .primary: pressed ? MTA.accent.opacity(0.8) : MTA.accent
    case .secondary: pressed ? MTA.raised : .clear
    case .dark: pressed ? MTA.accent : MTA.inverse
    }
  }
}

extension ButtonStyle where Self == MTAButtonStyle {
  static var mtaPrimary: MTAButtonStyle { .init(kind: .primary) }
  static var mtaSecondary: MTAButtonStyle { .init(kind: .secondary) }
  static func mtaSecondary(height: CGFloat) -> MTAButtonStyle { .init(kind: .secondary, height: height) }
}

// MARK: - Segmented (outlined pill, selected = inverse)

struct MTASegmented: View {
  let options: [String]
  @Binding var selection: Int

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options.indices, id: \.self) { i in
        Button { withAnimation(.snappy) { selection = i } } label: {
          Text(options[i]).mta(.button2)
            .foregroundStyle(i == selection ? MTA.textInverse : MTA.text)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background { if i == selection { Capsule().fill(MTA.inverse) } }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(i == selection ? .isSelected : [])
      }
    }
    .padding(3)
    .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 2) }
  }
}

// MARK: - Chips

struct Chip: View {
  let text: String
  var systemImage: String?
  var color: Color = MTA.text

  var body: some View {
    HStack(spacing: 4) {
      if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
      Text(text).mta(.label)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 9).padding(.vertical, 4)
    .overlay { Capsule().strokeBorder(color, lineWidth: 1.5) }
  }
}

/// Online / offline chip (icloud / icloud.slash).
struct ConnectionChip: View {
  @Environment(Connectivity.self) private var net
  var body: some View {
    Chip(text: net.isOnline ? (net.isExpensive ? "Cellular" : "Online") : "Offline",
         systemImage: net.isOnline ? "icloud" : "icloud.slash")
  }
}

/// Where a result came from: iphone (on-device) / icloud (cloud).
struct SourceChip: View {
  let source: InferenceSource
  let latencyMs: Int
  var body: some View {
    Chip(text: "\(source == .onDevice ? "On-device" : "Cloud · Gemini") · \(Self.format(latencyMs))",
         systemImage: source == .onDevice ? "iphone" : "icloud",
         color: source == .onDevice ? MTA.onTrack : MTA.accent)
  }
  static func format(_ ms: Int) -> String { ms >= 1000 ? String(format: "%.1f s", Double(ms) / 1000) : "\(ms) ms" }
}

// MARK: - Ask bar (opens Ask)

struct AskBar: View {
  let placeholder: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack {
        Text(placeholder).mta(.body1).foregroundStyle(MTA.text2)
        Spacer()
        Image(systemName: "arrow.up")
          .font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.onColor)
          .frame(width: 40, height: 40).background(MTA.accent, in: .circle)
      }
      .padding(.leading, 20).padding(.trailing, 6)
      .frame(height: 52)
      .background(MTA.surface, in: .capsule)
      .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 2) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Ask about your trip")
  }
}

// MARK: - Screen scaffolding

extension View {
  /// MTA screen: 30pt side margins on the black/white surface.
  func mtaScreen() -> some View {
    padding(.horizontal, MTA.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct MTAToggleRow: View {
  let title: String
  @Binding var isOn: Bool
  var body: some View {
    Toggle(isOn: $isOn) { Text(title).mta(.body1).foregroundStyle(MTA.text) }
      .tint(MTA.onTrack)
      .frame(minHeight: 52)
      .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
  }
}

struct MTAValueRow: View {
  let title: String
  let value: String
  var body: some View {
    HStack {
      Text(title).mta(.body1).foregroundStyle(MTA.text)
      Spacer()
      Text(value).mta(.body2).foregroundStyle(MTA.text2)
    }
    .frame(minHeight: 52)
    .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
  }
}

// MARK: - Brand badge: asterisk with "TRAVEL COPILOT" set on a circle around it

struct BrandBadge: View {
  var color: Color = MTA.onColor
  var size: CGFloat = 132
  var text = "TRAVEL COPILOT · TRAVEL COPILOT · "
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spin = false

  var body: some View {
    let chars = Array(text)
    let radius = size / 2 - 8
    ZStack {
      ZStack {
        ForEach(chars.indices, id: \.self) { i in
          Text(String(chars[i]))
            .font(MTAType.label.font)
            .foregroundStyle(color)
            .offset(y: -radius)
            .rotationEffect(.degrees(Double(i) / Double(chars.count) * 360))
        }
      }
      .rotationEffect(.degrees(spin ? 360 : 0))
      Image(systemName: "asterisk")
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(color)
    }
    .frame(width: size, height: size)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Travel Copilot")
  }
}
