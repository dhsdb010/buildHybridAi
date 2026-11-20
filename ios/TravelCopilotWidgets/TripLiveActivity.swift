import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TravelCopilotWidgets: WidgetBundle {
  var body: some Widget {
    TripLiveActivity()
    EmergencyCardWidget()
    EmergencyCardControl()
  }
}

typealias TripState = TripActivityAttributes.ContentState

/// Lock Screen + Dynamic Island (Figma page 02 · Journey).
/// One step at a time toward a goal: the vehicle rides the track, the last stop is the goal.
/// Everything sits on one 4-column grid: 16 margin · 8 gutter; the "when" column and the
/// right-hand buttons are one column wide, so their edges line up.
struct TripLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TripActivityAttributes.self) { context in
      LockScreenView(state: context.state)
        .activityBackgroundTint(Color(white: 0.11))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "travelcopilot://home"))
    } dynamicIsland: { context in
      let s = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Bullet(glyph: s.glyph, color: statusTint(s), size: 36).padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          When(state: s, big: 20).frame(width: Grid.col).padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 0) {
            Text(s.label.uppercased()).font(.custom("HelveticaNeue-Bold", size: 11)).tracking(0.9)
              .foregroundStyle(.white.opacity(0.6)).lineLimit(1).frame(height: 16)
            Text(s.title).font(.custom("HelveticaNeue-Bold", size: 20)).foregroundStyle(.white)
              .lineLimit(1).minimumScaleFactor(0.7).frame(height: 26)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 10) {
            if s.stops.count > 1 { JourneyTrack(state: s, labels: false) } else { Track(state: s) }
            Actions(state: s)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Bullet(glyph: s.glyph, color: statusTint(s), size: 24)
      } compactTrailing: {
        BigTime(state: s).font(.system(size: 15, weight: .semibold)).frame(maxWidth: 72)
      } minimal: {
        Bullet(glyph: s.glyph, color: statusTint(s), size: 24)
      }
      .keylineTint(statusTint(s))
    }
  }
}

/// Grid: 4 columns inside 16 pt margins with 8 pt gutters (Lock Screen width ≈ 370).
private enum Grid {
  static let margin: CGFloat = 16
  static let gutter: CGFloat = 8
  static let col: CGFloat = 80
}

private func color(_ p: TripProgress) -> Color {
  let h = p.hex
  return Color(red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255)
}
private func statusTint(_ s: TripState) -> Color { s.arrived ? color(.next) : color(s.progress) }

private let accent = Color(red: 0, green: 80 / 255, blue: 234 / 255)
private let surface = Color(white: 0.11)

private let hhmm: DateFormatter = {
  let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
}()
private let dayMonth: DateFormatter = {
  let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE d MMM"; return f
}()
private let shortDay: DateFormatter = {
  let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"; return f
}()

/// Countdown only inside the hour; otherwise the clock time (with the day above it when it isn't today).
private enum WhenRule {
  static func isCountdown(_ s: TripState) -> Bool {
    let dt = s.start.timeIntervalSinceNow
    return !s.arrived && dt > 0 && dt < 3600
  }
  static func top(_ s: TripState) -> (String, Color) {
    if s.arrived { return ("ARRIVED", color(.next)) }
    let dt = s.start.timeIntervalSinceNow
    if dt <= 3600 { return (s.progress.pill.uppercased(), s.progress == .now ? Color(red: 0.3, green: 0.55, blue: 1) : color(s.progress)) }
    let cal = Calendar.current
    if cal.isDateInToday(s.start) { return ("TODAY", .white.opacity(0.6)) }
    if cal.isDateInTomorrow(s.start) { return ("TOMORROW", .white.opacity(0.6)) }
    return (dayMonth.string(from: s.start).uppercased(), .white.opacity(0.6))
  }
}

/// Big number: live countdown under an hour, clock time otherwise.
private struct BigTime: View {
  let state: TripState
  var compact = false
  var body: some View {
    if WhenRule.isCountdown(state) {
      Text(timerInterval: Date.now...state.start, countsDown: true)
        .monospacedDigit().multilineTextAlignment(.trailing).foregroundStyle(.white)
    } else if !state.arrived && !Calendar.current.isDateInToday(state.start) {
      Text("\(shortDay.string(from: state.start)) \(hhmm.string(from: state.start))").foregroundStyle(.white)
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    } else {
      Text(hhmm.string(from: state.start)).monospacedDigit().foregroundStyle(.white)
    }
  }
}

/// "When" column: status/day word on top, the time below — same two line heights as the "what" column.
private struct When: View {
  let state: TripState
  var big: CGFloat = 24
  var body: some View {
    let (top, c) = WhenRule.top(state)
    VStack(alignment: .trailing, spacing: 0) {
      Text(top).font(.custom("HelveticaNeue-Bold", size: 11)).tracking(0.9).foregroundStyle(c)
        .lineLimit(1).minimumScaleFactor(0.7).frame(height: 15)
      Group {
        if WhenRule.isCountdown(state) || state.arrived || Calendar.current.isDateInToday(state.start) || state.start <= .now {
          BigTime(state: state)
        } else {
          Text(hhmm.string(from: state.start)).monospacedDigit().foregroundStyle(.white)
        }
      }
      .font(.custom("HelveticaNeue-Bold", size: big)).lineLimit(1).minimumScaleFactor(0.6)
      .frame(height: big + 4)
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// MTA subway-style bullet: status fill, glyph says how you travel.
private struct Bullet: View {
  let glyph: String
  let color: Color
  let size: CGFloat
  var body: some View {
    Image(systemName: glyph)
      .font(.system(size: size * 0.46, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color, in: .circle)
  }
}

/// from ●━━━━━○ to — a single moment (no journey): fills with the system timer.
private struct Track: View {
  let state: TripState
  var body: some View {
    let from = min(state.since, state.start.addingTimeInterval(-60))
    HStack(spacing: 6) {
      Text(state.from).font(.custom("HelveticaNeue-Bold", size: 12)).foregroundStyle(.white)
      Circle().fill(accent).frame(width: 10, height: 10)
      ProgressView(timerInterval: from...max(state.start, from.addingTimeInterval(60)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        .progressViewStyle(.linear)
        .tint(color(state.progress))
      Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2).frame(width: 10, height: 10)
      Text(state.to).font(.custom("HelveticaNeue-Bold", size: 12)).foregroundStyle(.white)
    }
  }
}

/// Narita ●━━━[🚌]━━━○ Shinjuku ━━━ (🛏) Hotel — the vehicle rides the segment you're on.
private struct JourneyTrack: View {
  let state: TripState
  var labels = true
  var body: some View {
    GeometryReader { g in
      let w = g.size.width
      let n = state.stops.count
      let x0: CGFloat = 5, x1 = w - 11
      let xs = (0..<n).map { x0 + (x1 - x0) * CGFloat($0) / CGFloat(max(n - 1, 1)) }
      let seg = min(max(state.segment, 0), max(n - 2, 0))
      let px = state.arrived ? x1 : xs[seg] + (xs[min(seg + 1, n - 1)] - xs[seg]) * state.along
      let c = statusTint(state)
      ZStack(alignment: .topLeading) {
        Capsule().fill(.white.opacity(0.22)).frame(width: w - 16, height: 4).offset(x: 5, y: 9)
        Capsule().fill(c).frame(width: max(px - 5, 1), height: 4).offset(x: 5, y: 9)
        ForEach(0..<n, id: \.self) { i in
          if i == n - 1 {
            Image(systemName: state.goalGlyph).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
              .frame(width: 20, height: 20)
              .background(state.arrived ? color(.next) : surface, in: .circle)
              .overlay { if !state.arrived { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2) } }
              .offset(x: w - 20, y: 1)
          } else {
            let passed = state.arrived || i <= seg
            Circle().fill(passed ? c : surface).frame(width: 10, height: 10)
              .overlay { if !passed { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2) } }
              .offset(x: xs[i] - 5, y: 6)
          }
          if labels {
            let on = state.arrived || i == seg || i == seg + 1
            Text(state.stops[i]).font(.custom(on ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium", size: 11))
              .foregroundStyle(.white.opacity(on ? 1 : 0.6)).lineLimit(1)
              .frame(width: 100, alignment: i == 0 ? .leading : i == n - 1 ? .trailing : .center)
              .offset(x: i == 0 ? 0 : i == n - 1 ? w - 100 : xs[i] - 50, y: 23)
          }
        }
        if !state.arrived {
          Image(systemName: state.glyph).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(c, in: .circle)
            .overlay { Circle().strokeBorder(surface, lineWidth: 3) }
            .offset(x: px - 11, y: 0)
        }
      }
    }
    .frame(height: labels ? 37 : 22)
  }
}

/// Bottom strip on the grid: card (cols 1–2) · Ask (col 3) · Done (col 4).
private struct Actions: View {
  let state: TripState
  var body: some View {
    HStack(spacing: Grid.gutter) {
      Link(destination: URL(string: state.cardLink) ?? URL(string: "travelcopilot://trip")!) {
        Chip(label: state.cardLabel.isEmpty ? state.action : state.cardLabel, glyph: state.cardGlyph, primary: state.arrived)
      }
      .frame(maxWidth: .infinity)
      Link(destination: askURL) { Chip(label: state.arrived || state.stepID.isEmpty ? "Ask AI" : "Ask", glyph: "asterisk", primary: false) }
        .frame(maxWidth: state.arrived || state.stepID.isEmpty ? .infinity : Grid.col)
      if !state.arrived && !state.stepID.isEmpty {
        Button(intent: JourneyDoneIntent(stepID: state.stepID)) { Chip(label: "Done", glyph: "checkmark", primary: true) }
          .buttonStyle(.plain)
          .frame(width: Grid.col)
      }
    }
  }

  private var askURL: URL {
    var c = URLComponents(string: "travelcopilot://ask")!
    c.queryItems = [URLQueryItem(name: "q", value: "About \(state.title): ")]
    return c.url!
  }
}

private struct Chip: View {
  let label: String
  let glyph: String
  let primary: Bool
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: glyph).font(.system(size: 13, weight: .semibold))
      Text(label).font(.custom("HelveticaNeue-Medium", size: 14)).lineLimit(1).minimumScaleFactor(0.8)
    }
    .foregroundStyle(primary ? .black : .white)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, minHeight: 28)
    .background(primary ? Color.white : Color.white.opacity(0.16), in: .capsule)
  }
}

/// Must fit the Lock Screen's 160 pt: 10 + header 16 + 6 + what/when 43 + 6 + track 37 + 4 + strip 38.
private struct LockScreenView: View {
  let state: TripState
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        // Header: brand mark · label ……… ref (same type, same baseline)
        HStack(spacing: 6) {
          Image(systemName: "asterisk").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 16, height: 16).background(accent, in: .rect(cornerRadius: 4))
          Text(state.label.uppercased()).font(.custom("HelveticaNeue-Bold", size: 11)).tracking(0.9)
            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
          Spacer(minLength: 8)
          if !state.ref.isEmpty {
            Text(state.ref).font(.custom("HelveticaNeue-Bold", size: 11)).tracking(0.9).foregroundStyle(.white.opacity(0.6))
          }
        }
        .frame(height: 16)
        // What (cols 1–3) · When (col 4): two lines each, same heights, so they line up.
        HStack(alignment: .top, spacing: Grid.gutter) {
          VStack(alignment: .leading, spacing: 0) {
            Text(state.info.isEmpty ? state.detail : state.info).font(.custom("HelveticaNeue", size: 13))
              .foregroundStyle(.white.opacity(0.7)).lineLimit(1).frame(height: 15)
            Text(state.title).font(.custom("HelveticaNeue-Bold", size: 24)).foregroundStyle(.white)
              .lineLimit(1).minimumScaleFactor(0.6).frame(height: 28)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          When(state: state).frame(width: Grid.col)
        }
        if state.stops.count > 1 { JourneyTrack(state: state) } else { Track(state: state).frame(height: 37) }
      }
      .padding(.horizontal, Grid.margin).padding(.top, 10).padding(.bottom, 4)

      Actions(state: state)
        .padding(.horizontal, Grid.margin).padding(.vertical, 5)
        .background(.black)
    }
  }
}
