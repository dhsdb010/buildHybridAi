import MapKit
import SwiftUI

struct DayIndex: Identifiable, Hashable { let id: Int }

/// One day of the plan: timed stops on a map (numbered pins, dashed route), the walk or taxi
/// between them, and a rough cost. Tap a stop to see it and change it; add your own.
struct DayPlanSheet: View {
  @Bindable var s: PlanSession
  @State var day: Int
  @Environment(AIService.self) private var ai
  @Environment(\.dismiss) private var dismiss
  @State private var editing: DayStop?
  @State private var adding = false
  @State private var loading = false
  @State private var error: String?

  private var stops: [DayStop] { s.dayStops[day] ?? [] }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          DayMap(stops: stops).frame(height: 230).id(stops.map(\.id))
          VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
              HStack(spacing: 8) {
                ForEach(s.outline.indices, id: \.self) { i in QuickChip(text: "Day \(i + 1)", selected: day == i) { day = i } }
              }
            }
            .scrollIndicators(.hidden)
            HStack {
              MTALabel("\(TripTimeline.dayTitle(s.dayDate(day))) · \(s.outline.indices.contains(day) ? s.outline[day].title : "")")
              Spacer()
              if !stops.isEmpty { Text("~$\(stops.map(\.cost).reduce(0, +)) est.").mta(.button2).foregroundStyle(MTA.accent) }
            }
            if loading {
              BlueTyping(caption: "Finding real places on the map")
            }
            if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
            ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
              Button { editing = stop } label: { StopRow(number: i + 1, stop: stop) }.buttonStyle(.plain)
              if i + 1 < stops.count {
                Text("⋮  " + DayStops.leg(stop, stops[i + 1])).mta(.body2).foregroundStyle(MTA.text2).padding(.leading, 9)
              }
            }
            if !stops.isEmpty {
              Text("Places from Apple Maps. Times and costs are estimates; tap a stop to change it.")
                .mta(.body2).foregroundStyle(MTA.text2)
            }
            Button("Add a stop") { adding = true }.buttonStyle(.mtaSecondary).padding(.top, 4)
          }
          .padding(.horizontal, MTA.margin)
        }
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .navigationTitle("\(s.idea?.city ?? "Trip") · Day \(day + 1)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
      .task(id: day) { await load() }
      .sheet(item: $editing) { stop in
        StopDetailView(stop: stop, onSave: { replace($0) }, onRemove: { s.dayStops[day]?.removeAll { $0.id == stop.id } })
      }
      .sheet(isPresented: $adding) {
        AddStopSheet(day: s.dayDate(day), city: s.idea?.city ?? "", near: s.center) { stop in
          s.dayStops[day, default: []].append(stop)
          s.dayStops[day]?.sort { $0.time < $1.time }
        }
        .presentationDetents([.medium])
      }
    }
  }

  private func replace(_ stop: DayStop) {
    guard let i = s.dayStops[day]?.firstIndex(where: { $0.id == stop.id }) else { return }
    s.dayStops[day]?[i] = stop
    s.dayStops[day]?.sort { $0.time < $1.time }
  }

  private func load() async {
    guard s.dayStops[day] == nil, let idea = s.idea, s.outline.indices.contains(day) else { return }
    loading = true; error = nil
    defer { loading = false }
    do {
      s.dayStops[day] = try await DayStops.make(day: day, title: s.outline[day].title, area: s.outline[day].area,
                                                city: idea.city, date: s.dayDate(day), near: s.center, brief: s.brief, ai: ai)
    } catch {
      self.error = "Couldn't plan this day: \(error.localizedDescription)"
    }
  }
}

struct StopRow: View {
  let number: Int
  let stop: DayStop
  var body: some View {
    HStack(spacing: 12) {
      Text("\(number)").mta(.label).foregroundStyle(MTA.onColor).frame(width: 28, height: 28).background(MTA.accent, in: .circle)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(TripTimeline.time(stop.time)).mta(.button2).foregroundStyle(MTA.text).monospacedDigit()
          KindTag(text: stop.kind)
        }
        Text(stop.name).mta(.body1).foregroundStyle(MTA.text).lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(stop.cost == 0 ? "Free" : "~$\(stop.cost)").mta(.body2).foregroundStyle(MTA.text2)
      Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
    }
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}

struct KindTag: View {
  let text: String
  var body: some View {
    Text(text.uppercased()).mta(.label).foregroundStyle(MTA.text2)
      .padding(.horizontal, 8).padding(.vertical, 3).background(MTA.raised, in: .rect(cornerRadius: 6))
  }
}

/// Numbered pins and a dashed route between the day's stops.
struct DayMap: View {
  let stops: [DayStop]
  var body: some View {
    Map(initialPosition: .automatic) {
      if stops.count > 1 {
        MapPolyline(coordinates: stops.map(\.coordinate))
          .stroke(MTA.text2, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
      }
      ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
        Annotation(stop.name, coordinate: stop.coordinate) {
          Text("\(i + 1)").mta(.label).foregroundStyle(MTA.onColor).frame(width: 28, height: 28)
            .background(MTA.accent, in: .circle).overlay { Circle().strokeBorder(.white, lineWidth: 2) }
        }
        .annotationTitles(.hidden)
      }
    }
    .mapStyle(.standard(pointsOfInterest: .excludingAll))
    .overlay { if stops.isEmpty { MTA.raised } }
  }
}

/// A stop up close: Apple Maps Look Around imagery, what it is, and its time, cost and note,
/// all editable. Used in the plan chat and again from Plan a day after saving.
struct StopDetailView: View {
  @State var stop: DayStop
  var onSave: (DayStop) -> Void
  var onRemove: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var scene: MKLookAroundScene?
  @State private var sceneChecked = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          photo
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              KindTag(text: stop.kind)
              if !stop.address.isEmpty { Text(stop.address).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1) }
            }
            TextField("Name", text: $stop.name).mta(.headline).foregroundStyle(MTA.text)
            if !stop.why.isEmpty { Text(stop.why).mta(.body1).foregroundStyle(MTA.text2) }
          }
          OutlineCard(stroke: MTA.border) {
            DatePicker("Time", selection: $stop.time, displayedComponents: .hourAndMinute).mta(.body1).tint(MTA.accent)
            HStack {
              Text("Cost per person (est.)").mta(.body1).foregroundStyle(MTA.text2)
              Spacer()
              Text("$").mta(.body1).foregroundStyle(MTA.text2)
              TextField("0", value: $stop.cost, format: .number).mta(.body1).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(width: 70)
            }
            TextField("Note, e.g. try the mentaiko", text: $stop.note, axis: .vertical).mta(.body1).lineLimit(1...3)
          }
          Button("Open in Maps") { if let url = mapsURL { openURL(url) } }.buttonStyle(.mtaSecondary)
          if let onRemove {
            Button("Remove from this day", role: .destructive) { onRemove(); dismiss() }
              .mta(.button2).foregroundStyle(MTA.urgent).frame(maxWidth: .infinity)
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) {
        Button("Save changes") { onSave(stop); dismiss() }.buttonStyle(.mtaPrimary)
          .padding(.horizontal, MTA.margin).padding(.bottom, 8)
      }
      .navigationTitle("Stop")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
      .task {
        if stop.latitude == 0 && stop.longitude == 0, let c = await MapService.search(stop.name) {
          stop.latitude = c.latitude; stop.longitude = c.longitude
        }
        scene = try? await MKLookAroundSceneRequest(coordinate: stop.coordinate).scene
        sceneChecked = true
      }
    }
  }

  @ViewBuilder private var photo: some View {
    ZStack(alignment: .bottomLeading) {
      if let scene {
        LookAroundPreview(initialScene: scene, allowsNavigation: true, badgePosition: .topTrailing)
      } else {
        Rectangle().fill(MTA.raised)
          .overlay {
            if sceneChecked {
              Label("No street photo here yet", systemImage: "photo").mta(.body2).foregroundStyle(MTA.text2)
            } else { ProgressView() }
          }
      }
    }
    .frame(height: 200)
    .clipShape(.rect(cornerRadius: 16))
  }

  private var mapsURL: URL? {
    var c = URLComponents(string: "https://maps.apple.com/")
    c?.queryItems = [.init(name: "q", value: stop.name)]
    if stop.latitude != 0 || stop.longitude != 0 { c?.queryItems?.append(.init(name: "ll", value: "\(stop.latitude),\(stop.longitude)")) }
    return c?.url
  }
}

/// Add your own stop: what and when. Apple Maps finds the place.
struct AddStopSheet: View {
  let day: Date
  let city: String
  let near: CLLocationCoordinate2D?
  var onAdd: (DayStop) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var time: Date
  @State private var finding = false
  @State private var error: String?

  init(day: Date, city: String, near: CLLocationCoordinate2D?, onAdd: @escaping (DayStop) -> Void) {
    self.day = day; self.city = city; self.near = near; self.onAdd = onAdd
    _time = State(initialValue: TripTimeline.calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day) ?? day)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        MTALabel(TripTimeline.dayTitle(day))
        TextField("Where? e.g. Ohori Park", text: $name).mta(.body1).padding(14)
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }
        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).mta(.body1).tint(MTA.accent)
        if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
        Spacer()
        Button(finding ? "Finding it on the map…" : "Add stop") { Task { await add() } }
          .buttonStyle(.mtaPrimary).disabled(name.nilIfEmpty == nil || finding)
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 16)
      .background(MTA.surface)
      .navigationTitle("Add a stop")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
    }
  }

  private func add() async {
    finding = true; error = nil
    defer { finding = false }
    guard let hit = await DayStops.find("\(name), \(city)", near: near) else {
      error = "Couldn't find \"\(name)\" near \(city). Try its full name."
      return
    }
    onAdd(DayStop(time: time, kind: "Stop", name: hit.name ?? name, why: "", address: hit.address,
                  latitude: hit.coordinate.latitude, longitude: hit.coordinate.longitude, cost: 0))
    dismiss()
  }
}

/// Destination photo from Wikipedia, with credit.
struct CityPhotoView: View {
  let city: String
  let country: String
  @State private var url: URL?
  var body: some View {
    MTA.raised
      .overlay {
        if let url { AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { MTA.raised } }
      }
      .frame(height: 140).frame(maxWidth: .infinity)
      .clipShape(.rect(cornerRadius: 16))
      .overlay(alignment: .bottomLeading) {
        if url != nil {
          Text("PHOTO · WIKIPEDIA").mta(.label).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.55), in: .rect(cornerRadius: 6)).padding(10)
        }
      }
    .accessibilityHidden(true)
    .task(id: city) { url = await CityPhoto.url(for: city, country: country) }
  }
}
