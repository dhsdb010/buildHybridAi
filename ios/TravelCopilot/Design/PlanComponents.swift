import SwiftUI

// Components for the Plan chat (Figma page 04, "Plan chat" column).

/// A ready-made starting point for the planner (Home, when there's no trip yet).
struct PlanTemplate: Identifiable, Hashable, Sendable {
  let countryCode: String
  let city: String
  let days: Int
  let theme: String
  var id: String { city }

  static let all: [PlanTemplate] = [
    .init(countryCode: "JP", city: "Tokyo", days: 5, theme: "Food & design"),
    .init(countryCode: "KR", city: "Seoul", days: 4, theme: "Night markets & cafés"),
    .init(countryCode: "FR", city: "Paris", days: 5, theme: "Museums & bakeries"),
    .init(countryCode: "IT", city: "Rome", days: 4, theme: "History & pasta"),
  ]
  /// Only places where the on-device model speaks the language (offline help works there).
  static var available: [PlanTemplate] {
    let codes = Set(PlanLanguages.countries().map(\.code))
    return all.filter { codes.contains($0.countryCode) }
  }
  var country: PlanCountry? { PlanLanguages.catalog.first { $0.code == countryCode } }
}

/// MTA lifestyle poster card for a trip idea.
struct TemplateCard: View {
  let template: PlanTemplate
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        MTALabel("\(template.country?.name ?? "") · \(template.days) days", color: MTA.onColor.opacity(0.85))
        Spacer(minLength: 0)
        Text(template.city).mta(.headline).foregroundStyle(MTA.onColor)
        HStack {
          Text(template.theme).mta(.body2).foregroundStyle(MTA.onColor)
          Spacer(minLength: 4)
          Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(MTA.onColor)
        }
      }
      .padding(16)
      .frame(width: 200, height: 140, alignment: .leading)
      .background(MTA.accent, in: .rect(cornerRadius: 20))
      .overlay(alignment: .topTrailing) {
        Image(systemName: "asterisk").font(.system(size: 22, weight: .semibold)).foregroundStyle(MTA.onColor.opacity(0.35)).padding(14)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Plan \(template.days) days in \(template.city): \(template.theme)")
  }
}

/// Title first, then the icon ("Prepare my trip →").
struct TrailingIcon: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 8) { configuration.title; configuration.icon }
  }
}

/// Quick answer. Selected = New Blue fill.
struct QuickChip: View {
  let text: String
  var selected = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(text).mta(.button2)
        .foregroundStyle(selected ? MTA.onColor : MTA.text)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background { if selected { Capsule().fill(MTA.accent) } }
        .overlay { if !selected { Capsule().strokeBorder(MTA.border, lineWidth: 2) } }
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// AI turn: plain text with the asterisk, no bubble.
struct ChatAI: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "asterisk").font(.system(size: 18, weight: .semibold)).foregroundStyle(MTA.accent)
        .padding(.top, 3).accessibilityHidden(true)
      Text(text).mta(.body1).foregroundStyle(MTA.text).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// The user's turn: raised pill, right-aligned.
struct ChatYou: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    HStack {
      Spacer(minLength: 52)
      Text(text).mta(.body1).foregroundStyle(MTA.text)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(MTA.raised, in: .rect(cornerRadius: 20))
    }
  }
}

/// "Plan so far": Where · When · Stay · Eat · See · Book.
struct PlanBar: View {
  static let steps = ["Where", "When", "Stay", "Eat", "See", "Book"]
  let current: Int
  var onTap: ((Int) -> Void)?
  var body: some View {
    HStack(spacing: 0) {
      ForEach(Self.steps.indices, id: \.self) { i in
        Button { onTap?(i) } label: {
          VStack(spacing: 6) {
            ZStack {
              if i < current {
                Circle().fill(MTA.onTrack)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(MTA.onColor)
              } else if i == current {
                Circle().fill(MTA.accent)
                Text("\(i + 1)").mta(.label).foregroundStyle(MTA.onColor)
              } else {
                Circle().strokeBorder(MTA.subtle, lineWidth: 2)
                Text("\(i + 1)").mta(.label).foregroundStyle(MTA.text2)
              }
            }
            .frame(width: 28, height: 28)
            MTALabel(Self.steps[i], color: i <= current ? MTA.text : MTA.text2)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onTap != nil && i <= current)
        .accessibilityLabel("\(Self.steps[i]), \(i < current ? "done" : i == current ? "current" : "to do")")
      }
    }
  }
}

/// Where the plan comes from (online only).
struct PlanOnlineRow: View {
  @Environment(Connectivity.self) private var net
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: net.isOnline ? "icloud" : "icloud.slash").font(.system(size: 12, weight: .semibold))
        .foregroundStyle(net.isOnline ? MTA.accent : MTA.obstacle)
      MTALabel(net.isOnline ? "Online · Cloud · Gemini + Maps" : "Offline · planning needs internet")
    }
  }
}

/// A score or fact badge on an option card. With a URL it's a link ("Tabelog ↗").
struct ScoreBadge: View {
  let label: String
  let value: String
  var url: URL?
  var body: some View {
    let content = HStack(spacing: 6) {
      MTALabel(label)
      Text(value).mta(.button2).foregroundStyle(MTA.text)
      if url != nil { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(MTA.text) }
    }
    .padding(.horizontal, 10).padding(.vertical, 5)
    .background(MTA.raised, in: .rect(cornerRadius: 12))
    if let url { Link(destination: url) { content } } else { content }
  }
}

/// Wraps children onto new lines (chips, badges).
struct FlowLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    rows(proposal.width ?? .infinity, subviews).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (i, p) in rows(bounds.width, subviews).points.enumerated() {
      subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
    }
  }
  private func rows(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
    var points: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0; var maxX: CGFloat = 0
    for s in subviews {
      let size = s.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
      points.append(CGPoint(x: x, y: y))
      x += size.width + spacing; rowH = max(rowH, size.height); maxX = max(maxX, x - spacing)
    }
    return (points, CGSize(width: maxX, height: y + rowH))
  }
}

/// Suggestion card (destination, hotel, food, sight). Default / Kept.
struct OptionCard: View {
  let label: String
  let source: String
  let title: String
  let why: String
  var badges: [ScoreBadge] = []
  var facts: String?
  var kept = false
  var mapsURL: URL?
  var onKeep: () -> Void
  var onSwap: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack { MTALabel(label); Spacer(); MTALabel(source) }
      Text(title).mta(.subheadNormal).foregroundStyle(MTA.text)
      if !why.isEmpty { Text(why).mta(.body2).foregroundStyle(MTA.text2) }
      if !badges.isEmpty { FlowLayout(spacing: 8) { ForEach(badges.indices, id: \.self) { badges[$0] } } }
      if let facts, !facts.isEmpty { Text(facts).mta(.body2).foregroundStyle(MTA.text) }
      HStack(spacing: 8) {
        Button(action: onKeep) {
          Label(kept ? "Kept" : "Keep", systemImage: kept ? "checkmark" : "plus")
            .labelStyle(.titleAndIcon).mta(.button2).foregroundStyle(MTA.onColor)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(kept ? MTA.onTrack : MTA.accent, in: .capsule)
        }
        if let onSwap { pill("Swap", action: onSwap) }
        if let mapsURL { Link(destination: mapsURL) { pillLabel("Maps") } }
      }
      .buttonStyle(.plain)
      .padding(.top, 6)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTA.surface, in: .rect(cornerRadius: 20))
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(kept ? MTA.onTrack : MTA.border, lineWidth: 2) }
  }

  private func pill(_ text: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { pillLabel(text) }
  }
  private func pillLabel(_ text: String) -> some View {
    Text(text).mta(.button2).foregroundStyle(MTA.text)
      .padding(.horizontal, 16).padding(.vertical, 8)
      .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 2) }
  }
}

/// Hand-off row: book on the airline / hotel site.
struct BookRow: View {
  let systemImage: String
  let title: String
  let detail: String
  let url: URL?
  var body: some View {
    HStack(spacing: 14) {
      TripBullet(systemName: systemImage, status: .accent, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).mta(.body1).foregroundStyle(MTA.text)
        Text(detail).mta(.body2).foregroundStyle(MTA.text2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let url {
        Link(destination: url) {
          Text("Open").mta(.button2).foregroundStyle(MTA.onColor)
            .padding(.horizontal, 16).padding(.vertical, 8).background(MTA.accent, in: .capsule)
        }
      }
    }
    .padding(.vertical, 8)
  }
}
