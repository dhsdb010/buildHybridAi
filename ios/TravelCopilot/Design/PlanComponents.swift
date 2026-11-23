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
    HStack(alignment: .bottom, spacing: 8) {
      BlueAvatar()
      Text(text).mta(.body1).foregroundStyle(MTA.text)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(MTA.raised, in: .rect(cornerRadius: 20))
      Spacer(minLength: 40)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Blue: \(text)")
  }
}

/// The user's turn: blue bubble on the right, as in Ask.
struct ChatYou<Extra: View>: View {
  let text: String
  let extra: Extra
  init(_ text: String, @ViewBuilder extra: () -> Extra) { self.text = text; self.extra = extra() }
  var body: some View {
    HStack {
      Spacer(minLength: 52)
      VStack(alignment: .leading, spacing: 8) {
        extra
        if !text.isEmpty { Text(text).mta(.body1).foregroundStyle(MTA.onColor) }
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(MTA.accent, in: .rect(cornerRadius: 20))
    }
    .accessibilityElement(children: .combine)
  }
}

extension ChatYou where Extra == EmptyView {
  init(_ text: String) { self.text = text; self.extra = EmptyView() }
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
  /// A pasted confirmation for this item is in the Vault: show "Booked" instead of the link.
  var booked = false
  var body: some View {
    HStack(spacing: 14) {
      TripBullet(systemName: systemImage, status: booked ? .onTrack : .accent, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).mta(.body1).foregroundStyle(MTA.text).lineLimit(1)
        Text(detail).mta(.body2).foregroundStyle(MTA.text2).lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if booked {
        Text("Booked").mta(.button2).foregroundStyle(MTA.text)
          .padding(.horizontal, 14).padding(.vertical, 6)
          .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 2) }
      } else if let url {
        Link(destination: url) {
          Text("Open").mta(.button2).foregroundStyle(MTA.onColor)
            .padding(.horizontal, 16).padding(.vertical, 8).background(MTA.accent, in: .capsule)
        }
      }
    }
    .padding(.vertical, 8)
  }
}

/// "Flight · SFO ⇄ HND      ~$950–1,200" rows, and a bold total. Estimates only, labelled as such.
struct CostLine: View {
  let label: String
  let value: String
  var total = false
  var body: some View {
    HStack {
      Text(label).mta(total ? .subheadNormal : .body1).foregroundStyle(total ? MTA.text : MTA.text2)
      Spacer(minLength: 8)
      Text(value).mta(total ? .subheadNormal : .body1).foregroundStyle(total ? MTA.accent : MTA.text).monospacedDigit()
    }
  }
}

/// Month calendar for picking the trip: tap the first day, then the last day.
struct RangeCalendar: View {
  @Binding var start: Date
  @Binding var end: Date
  /// Earliest day you can pick (today).
  var from: Date
  @State private var month: Date
  @State private var pickingEnd = false

  init(start: Binding<Date>, end: Binding<Date>, from: Date) {
    _start = start; _end = end; self.from = from
    _month = State(initialValue: TripTimeline.calendar.dateInterval(of: .month, for: start.wrappedValue)?.start ?? start.wrappedValue)
  }

  private var cal: Calendar { TripTimeline.calendar }

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text(month.formatted(.dateTime.month(.wide).year())).mta(.subheadNormal).foregroundStyle(MTA.text)
        Spacer()
        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
          .disabled(month <= (cal.dateInterval(of: .month, for: from)?.start ?? from))
          .accessibilityLabel("Previous month")
        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
          .accessibilityLabel("Next month")
      }
      .foregroundStyle(MTA.accent)
      HStack(spacing: 0) {
        ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
          Text(d).mta(.label).foregroundStyle(MTA.text2).frame(maxWidth: .infinity)
        }
      }
      ForEach(weeks, id: \.self) { week in
        HStack(spacing: 0) {
          ForEach(Array(week.enumerated()), id: \.offset) { _, day in cell(day) }
        }
      }
    }
    .padding(14)
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.border, lineWidth: 2) }
  }

  /// Weeks of the shown month, Sunday first; nil = blank cell.
  private var weeks: [[Date?]] {
    guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
    let lead = cal.component(.weekday, from: month) - 1
    var days: [Date?] = Array(repeating: nil, count: lead)
    days += range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    while days.count % 7 != 0 { days.append(nil) }
    return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
  }

  @ViewBuilder private func cell(_ day: Date?) -> some View {
    if let day {
      let d = cal.startOfDay(for: day)
      let s = cal.startOfDay(for: start), e = cal.startOfDay(for: end)
      let isStart = d == s, isEnd = d == e && !pickingEnd
      let inside = !pickingEnd && d > s && d < e
      let past = d < cal.startOfDay(for: from)
      Button { tap(d) } label: {
        ZStack {
          if inside || ((isStart || isEnd) && !pickingEnd && s != e) {
            Rectangle().fill(MTA.raised)
              .padding(.leading, isStart ? 22 : 0).padding(.trailing, isEnd ? 22 : 0)
          }
          if isStart || isEnd { Circle().fill(MTA.accent).frame(width: 38, height: 38) }
          Text("\(cal.component(.day, from: d))").mta(isStart || isEnd ? .button2 : .body1)
            .foregroundStyle(isStart || isEnd ? MTA.onColor : (past ? MTA.subtle : MTA.text))
        }
        .frame(maxWidth: .infinity).frame(height: 40).contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabled(past)
      .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
      .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
    } else {
      Color.clear.frame(maxWidth: .infinity).frame(height: 40)
    }
  }

  private func tap(_ d: Date) {
    if pickingEnd && d >= cal.startOfDay(for: start) {
      end = d; pickingEnd = false
    } else {
      start = d; end = d; pickingEnd = true
    }
  }

  private func shift(_ n: Int) { if let m = cal.date(byAdding: .month, value: n, to: month) { month = m } }
}

/// Budget slider: the value in a bubble above the thumb, a New Blue fill, min and max under the track.
struct BudgetSlider: View {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  private let thumb: CGFloat = 28

  var body: some View {
    VStack(spacing: 6) {
      GeometryReader { geo in
        let width = geo.size.width - thumb
        let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let x = width * frac
        ZStack(alignment: .topLeading) {
          Text(PlanBudget.label(Int(value)) + (value >= range.upperBound ? "+" : ""))
            .mta(.button2).foregroundStyle(MTA.onColor).monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(MTA.accent, in: .capsule)
            .fixedSize()
            .frame(width: 120)
            .offset(x: min(max(x + thumb / 2 - 60, -10), geo.size.width - 110), y: 0)
          Capsule().fill(MTA.raised).frame(height: 8).offset(y: 44)
          Capsule().fill(MTA.accent).frame(width: x + thumb / 2, height: 8).offset(y: 44)
          Circle().fill(MTA.surface)
            .overlay { Circle().strokeBorder(MTA.accent, lineWidth: 3) }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .frame(width: thumb, height: thumb)
            .offset(x: x, y: 34)
        }
        // The whole 64pt-tall area takes the drag (offsets don't grow the hit area), and it wins over the scroll view.
        .frame(width: geo.size.width, height: 64, alignment: .topLeading)
        .contentShape(.rect)
        .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { g in
          let f = min(max((g.location.x - thumb / 2) / width, 0), 1)
          let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
          let snapped = (raw / step).rounded() * step
          if snapped != value { value = snapped; UISelectionFeedbackGenerator().selectionChanged() }
        })
      }
      .frame(height: 64)
      HStack {
        Text(PlanBudget.label(Int(range.lowerBound))).mta(.body2).foregroundStyle(MTA.text2)
        Spacer()
        Text(PlanBudget.label(Int(range.upperBound)) + "+").mta(.body2).foregroundStyle(MTA.text2)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Budget per person")
    .accessibilityValue(PlanBudget.label(Int(value)))
    .accessibilityAdjustableAction { dir in
      switch dir {
      case .increment: value = min(range.upperBound, value + step * 5)
      case .decrement: value = max(range.lowerBound, value - step * 5)
      @unknown default: break
      }
    }
  }
}

/// "−  2  +" stepper in an outlined capsule (travelers).
struct CountStepper: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  let label: String

  var body: some View {
    HStack(spacing: 0) {
      Button { if value > range.lowerBound { value -= 1 } } label: {
        Image(systemName: "minus").frame(width: 44, height: 40)
      }
      .disabled(value <= range.lowerBound)
      .accessibilityLabel("Fewer")
      Text("\(value)").mta(.subheadNormal).foregroundStyle(MTA.text).monospacedDigit().frame(minWidth: 28)
      Button { if value < range.upperBound { value += 1 } } label: {
        Image(systemName: "plus").frame(width: 44, height: 40)
      }
      .disabled(value >= range.upperBound)
      .accessibilityLabel("More")
    }
    .font(.system(size: 17, weight: .semibold))
    .foregroundStyle(MTA.accent)
    .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 2) }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue("\(value)")
    .accessibilityAdjustableAction { dir in
      switch dir {
      case .increment: if value < range.upperBound { value += 1 }
      case .decrement: if value > range.lowerBound { value -= 1 }
      @unknown default: break
      }
    }
  }
}
