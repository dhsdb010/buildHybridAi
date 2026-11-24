import MapKit
import SwiftData
import SwiftUI

/// The trip's route: numbered stops joined by a dotted line (the last stop in accent blue).
struct TripRouteMap: View {
  let stops: [TripSummary.Stop]
  var interactive = false

  var body: some View {
    Map(initialPosition: Self.camera(stops), interactionModes: interactive ? .all : []) {
      let coords = stops.compactMap(Self.coordinate)
      if coords.count > 1 {
        MapPolyline(coordinates: coords).stroke(MTA.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
      }
      ForEach(Array(stops.enumerated()), id: \.element.id) { i, s in
        if let c = Self.coordinate(s) {
          Annotation(s.title, coordinate: c) {
            Text("\(i + 1)").mta(.label).foregroundStyle(MTA.onColor)
              .frame(width: 26, height: 26)
              .background(i == stops.count - 1 ? MTA.accent : .black, in: .circle)
              .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
          }
          .annotationTitles(.hidden)
        }
      }
    }
    .mapStyle(.standard(pointsOfInterest: .excludingAll))
    .id(stops.map(\.id))   // reframe when the day changes
    .clipShape(.rect(cornerRadius: 12))
    .accessibilityLabel("Map of your route, \(stops.count) stops")
  }

  /// Fits every stop, with a margin for the pins.
  static func camera(_ stops: [TripSummary.Stop]) -> MapCameraPosition {
    let cs = stops.compactMap(coordinate)
    guard let minLa = cs.map(\.latitude).min(), let maxLa = cs.map(\.latitude).max(),
          let minLo = cs.map(\.longitude).min(), let maxLo = cs.map(\.longitude).max() else { return .automatic }
    let center = CLLocationCoordinate2D(latitude: (minLa + maxLa) / 2, longitude: (minLo + maxLo) / 2)
    return .region(MKCoordinateRegion(center: center, span: .init(latitudeDelta: max((maxLa - minLa) * 1.5, 0.012),
                                                                  longitudeDelta: max((maxLo - minLo) * 1.5, 0.012))))
  }

  static func coordinate(_ s: TripSummary.Stop) -> CLLocationCoordinate2D? {
    guard let la = s.latitude, let lo = s.longitude else { return nil }
    return .init(latitude: la, longitude: lo)
  }
}

/// Home after the trip: the trip at a glance. Tap to open the full summary.
struct YourTripCard: View {
  let summary: TripSummary
  let expenses: Int
  let better: Int
  let steps: Int?

  var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          MTALabel(summary.dates, color: MTA.text)
          Spacer()
          Text("See it all ›").mta(.body2).foregroundStyle(MTA.accent)
        }
        if !summary.route.isEmpty {
          TripRouteMap(stops: summary.route).frame(height: 140).allowsHitTesting(false)
        }
        HStack(alignment: .top, spacing: 8) {
          stat("\(summary.places)", "Places")
          stat("\(expenses)", "Expenses")
          stat("\(better)", "Better")
          if let steps { stat(steps >= 1000 ? "\(steps / 1000)k" : "\(steps)", "Steps") } else { stat("\(summary.dayCount)", "Days") }
        }
      }
      .padding(16)
      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MTA.border, lineWidth: 2) }
      .contentShape(.rect)
      .accessibilityHint("Opens your trip summary")
  }

  private func stat(_ value: String, _ caption: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).mta(.headline).monospacedDigit().foregroundStyle(MTA.text)
      Text(caption).mta(.label).foregroundStyle(MTA.text)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// Your trip: the route on a map (tap a day), day by day, what you did, spending, and one more thing.
struct TripSummaryView: View {
  let summary: TripSummary
  let place: String
  let country: String
  @Environment(AppRouter.self) private var router
  @Query(sort: \ExpenseItem.spentAt) private var expenses: [ExpenseItem]
  @Query(filter: #Predicate<TranslationEntry> { $0.polishedTranslation != nil }) private var improved: [TranslationEntry]
  @Query private var translations: [TranslationEntry]
  @Query(filter: #Predicate<ChatMessage> { $0.role == "you" }) private var questions: [ChatMessage]
  @Query(filter: #Predicate<RoutingEntry> { $0.source == "onDevice" && $0.outcome == "ok" }) private var offline: [RoutingEntry]
  @State private var day: Date?
  @State private var steps: Int?
  @State private var counting = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 10) {
          MTALabel("\(country) · \(summary.dates)")
          Text("\(place), done.").mta(.displayMedium).foregroundStyle(MTA.text)
          Text("Built from your bookings, day plans and receipts. Nothing was tracked.")
            .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
        }

        if !summary.route.isEmpty {
          TripRouteMap(stops: summary.route(on: day), interactive: true).frame(height: 260)
          dayChips
        }

        MTALabel("Day by day", color: MTA.text).padding(.top, 4)
        timeline

        MTALabel("What you did", color: MTA.text).padding(.top, 4)
        whatYouDid

        spending
        oneMoreThing

        HStack(spacing: 10) {
          ShareLink(item: summary.shareText(place: place, steps: steps)) {
            Text("Share summary").frame(maxWidth: .infinity)
          }
          .buttonStyle(.mtaSecondary)
          Button("Plan next trip") { router.tab = .prepare }.buttonStyle(.mtaPrimary)
        }
      }
      .mtaScreen()
      .padding(.top, 8).padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
    .background(MTA.surface)
    .navigationTitle("Your trip")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: summary.shareText(place: place, steps: steps)) { Text("Share") }
      }
    }
    .task { steps = Steps.saved(summary.range) }
  }

  // MARK: Map days

  private var dayChips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        chip("All", on: day == nil) { day = nil }
        ForEach(summary.days.filter { d in d.stops.contains(where: \.hasCoordinate) }) { d in
          chip(d.day.formatted(.dateTime.weekday(.abbreviated).day()), on: day == d.day) { day = d.day }
        }
      }
      .padding(.horizontal, MTA.margin)
    }
    .scrollIndicators(.hidden)
    .padding(.horizontal, -MTA.margin)
  }

  private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: { withAnimation(.snappy) { action() } }) {
      Text(text).mta(.button2)
        .foregroundStyle(on ? MTA.textInverse : MTA.text)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(on ? MTA.inverse : .clear, in: .capsule)
        .overlay { Capsule().strokeBorder(MTA.border, lineWidth: on ? 0 : 1.5) }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  // MARK: Timeline

  private var timeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(summary.days) { d in
        MTALabel(d.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
          .padding(.top, 12).padding(.bottom, 4)
        ForEach(d.stops) { s in
          HStack(spacing: 12) {
            TripIcon(symbol: s.symbol)
            VStack(alignment: .leading, spacing: 1) {
              Text(s.title).mta(.button2).foregroundStyle(MTA.text).lineLimit(2)
              if !s.detail.isEmpty { Text(s.detail).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let n = summary.route.firstIndex(of: s) {
              Text("\(n + 1)").mta(.label).foregroundStyle(MTA.text2).accessibilityLabel("Stop \(n + 1) on the map")
            }
          }
          .padding(.vertical, 6)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  // MARK: What you did

  private var whatYouDid: some View {
    let home = Spend.homeCurrency
    let total = Spend.homeTotal(expenses, rate: ExpenseService.savedRate)
    let tiles: [(String, String)] = [
      ("\(summary.places)", "Places visited"),
      ("\(expenses.count)", total.map { "Expenses · \(Spend.money($0, home, whole: true))" } ?? "Expenses"),
      ("\(questions.count)", "Questions to Blue"),
      ("\(translations.filter { $0.direction == "out" }.count)", "Phrases said"),
      ("\(improved.count)", "Drafts made better"),
      ("\(offline.count)", "Answers offline"),
    ]
    return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
      ForEach(tiles, id: \.1) { v, c in
        VStack(alignment: .leading, spacing: 6) {
          Text(v).mta(.headline).monospacedDigit()
          Text(c).mta(.label).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(MTA.text)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }
        .accessibilityElement(children: .combine)
      }
    }
  }

  // MARK: Spending

  @ViewBuilder
  private var spending: some View {
    if !expenses.isEmpty {
      let home = Spend.homeCurrency
      let total = Spend.homeTotal(expenses, rate: ExpenseService.savedRate)
      let sum = Spend.localTotal(expenses)
      let top = Spend.byCategory(expenses).prefix(2).map { "\($0.category.title) \(Int((Spend.localTotal($0.items) / max(sum, 1) * 100).rounded()))%" }
      let status = Spend.status(spent: total ?? 0, budget: ExpenseService.budget)
      Button { router.tab = .trip; router.tripMode = 1 } label: {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            MTALabel("Spending", color: MTA.onColor)
            Text(([total.map { Spend.money($0, home) } ?? Spend.money(sum, expenses[0].currency)] + top).joined(separator: " · "))
              .mta(.button2).foregroundStyle(MTA.onColor).lineLimit(1).minimumScaleFactor(0.8)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.headline).foregroundStyle(MTA.onColor)
        }
        .padding(15)
        .background(status == .near ? MTA.obstacle : MTA.onTrack, in: .rect(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: One more thing (steps)

  private var oneMoreThing: some View {
    VStack(alignment: .leading, spacing: 8) {
      MTALabel("One more thing…", color: MTA.onColor.opacity(0.8))
      if let steps {
        Text("\(steps.formatted()) steps").mta(.displayMedium).monospacedDigit()
        let fujis = Steps.fujis(steps)
        Text("\(Steps.kmText(steps).prefix(1).uppercased() + Steps.kmText(steps).dropFirst()).\(fujis > 0 ? " That’s Mt. Fuji, \(fujis) time\(fujis == 1 ? "" : "s") over." : "")")
          .mta(.body2).fixedSize(horizontal: false, vertical: true)
        Text("From Health on this iPhone, only because you allowed it.").mta(.tab).opacity(0.7)
      } else {
        Text("How far did you walk?").mta(.headline)
        Text("Count your steps from \(summary.dates.components(separatedBy: " · ").first ?? "the trip"), read from Health on this iPhone.")
          .mta(.body2).fixedSize(horizontal: false, vertical: true)
        Button {
          counting = true
          Task { steps = await Steps.count(summary.range); counting = false }
        } label: {
          Label(counting ? "Counting…" : "Count my steps", systemImage: "figure.walk")
            .mta(.button2).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 10)
            .background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(counting)
        Text("Only if you allow it. Read only; nothing leaves this iPhone.").mta(.tab).opacity(0.7)
      }
    }
    .foregroundStyle(MTA.onColor)
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.black, in: .rect(cornerRadius: 20))
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.subtle, lineWidth: 1) }
    .accessibilityElement(children: .contain)
  }
}
