import SwiftUI
import SwiftData
import MapKit

/// Trip map, full screen. Live Apple Maps when online; the saved snapshot + GPS dot when offline.
/// Floating glass controls on top, a bottom sheet with places and the Ask bar (Figma: App Screens → Map).
struct MapScreen: View {
  @Environment(\.modelContext) private var context
  @Environment(\.colorScheme) private var scheme
  @Environment(Connectivity.self) private var net
  @Environment(LocationService.self) private var location
  @Environment(AppRouter.self) private var router
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query(sort: \TripPlan.start) private var plans: [TripPlan]
  @Query(sort: \Place.createdAt) private var places: [Place]
  @Query(sort: \MapPack.createdAt) private var packs: [MapPack]
  @Query private var destinationPacks: [DestinationPack]
  @State private var mode = 0              // 0 live · 1 offline
  @State private var area = 0
  @State private var selected: String?
  @State private var busy: String?
  @State private var error: String?
  @State private var taxiItem: VaultItem?
  @State private var camera: MapCameraPosition = .automatic
  @State private var expanded = false
  @State private var sheetHeight: CGFloat = 0

  private var hotel: Place? { places.first { $0.kind == "hotel" } }
  private var offline: Bool { mode == 1 || !net.isOnline }

  var body: some View {
    ZStack(alignment: .top) {
      // The sheet's height is added to the map's safe area, so the map centers on the visible part.
      mapLayer.ignoresSafeArea()
      controls.padding(.horizontal, MTA.margin).padding(.top, 4)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { sheet }
    .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: destinationPacks.first) }
    .onAppear {
      location.start()
      if !net.isOnline { mode = 1 }
      #if DEBUG
        if UserDefaults.standard.string(forKey: "mapMode") == "offline" { mode = 1 }
      #endif
      expanded = mode == 1
      if let hotel { focus(hotel, meters: 3000, animated: false) }
    }
    .onChange(of: net.isOnline) { _, online in if !online { mode = 1 } }
    .onChange(of: mode) { _, m in withAnimation(.snappy) { expanded = m == 1 } }
  }

  // MARK: - Map layer (full bleed)

  @ViewBuilder
  private var mapLayer: some View {
    if !offline {
      Map(position: $camera, selection: $selected) {
        ForEach(places) { p in
          Annotation(p.name, coordinate: .init(latitude: p.latitude, longitude: p.longitude)) {
            MapPin(place: p, selected: selected == p.name)
          }
          .annotationTitles(.hidden)
          .tag(p.name)
        }
        UserAnnotation()
      }
      .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .hotel, .pharmacy, .hospital, .police])))
      .mapControls { }
      .safeAreaPadding(.bottom, sheetHeight)
    } else if let pack = packs[safe: area] {
      OfflineMapView(pack: pack, places: places, here: location.location, dark: scheme == .dark, selected: $selected,
                     bottomInset: sheetHeight)
    } else {
      ZStack {
        MTA.raised
        VStack(spacing: 10) {
          Image(systemName: "icloud.slash").font(.system(size: 34, weight: .semibold)).foregroundStyle(MTA.text2)
          Text("No offline map saved yet").mta(.subheadNormal).foregroundStyle(MTA.text)
          Text("Download it on Wi-Fi so your hotel and places stay on the map with no signal.")
            .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center)
        }
        .padding(40)
      }
    }
  }

  // MARK: - Floating controls

  private var controls: some View {
    HStack(alignment: .top) {
      MTASegmented(options: ["Live", "Offline"], selection: $mode)
        .frame(width: 220)
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .disabled(!net.isOnline)
      Spacer()
      VStack(spacing: 12) {
        GlassIcon(systemName: net.isOnline ? "icloud" : "icloud.slash", color: net.isOnline ? MTA.accent : MTA.obstacle,
                  label: net.isOnline ? "Online" : "Offline") {}
          .allowsHitTesting(false)
        GlassIcon(systemName: "location.fill", color: MTA.accent, label: "Show where I am") { recenter() }
      }
    }
  }

  // MARK: - Bottom sheet

  private var sheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Capsule().fill(MTA.subtle).frame(width: 36, height: 5).frame(maxWidth: .infinity)
        .padding(.bottom, 2)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .accessibilityLabel(expanded ? "Show less" : "Show more")
        .accessibilityAddTraits(.isButton)

      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          MTALabel(offline ? "Saved map · works with no signal" : "\(cityName)\(places.count) places")
          Text(offline ? (packs[safe: area]?.name ?? "Offline map") : "Near you").mta(.subheadMedium).foregroundStyle(MTA.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        statusChip
      }

      if offline && packs.count > 1 {
        FlowLayout {
          ForEach(packs.indices, id: \.self) { i in QuickChip(text: packs[i].name, selected: i == area) { area = i } }
        }
      }

      if places.isEmpty {
        emptyActions
      } else {
        let shown = expanded ? places : Array(places.prefix(2))
        if shown.count > 4 {
          ScrollView { VStack(spacing: 0) { ForEach(shown) { placeRow($0) } } }
            .scrollIndicators(.hidden).frame(maxHeight: 300)
        } else {
          VStack(spacing: 0) { ForEach(shown) { placeRow($0) } }
        }
        if expanded { downloadActions }
      }
      if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }

      if !places.isEmpty {
        AskBar(placeholder: offline ? "How far is the station?" : "Where can I eat nearby?") { router.ask = AskRequest() }
      }
    }
    .padding(.horizontal, MTA.margin).padding(.top, 10).padding(.bottom, 12)
    .background {
      UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
        .fill(MTA.surface)
        .shadow(color: .black.opacity(0.16), radius: 24, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
    .gesture(DragGesture(minimumDistance: 20).onEnded { v in
      withAnimation(.snappy) { if v.translation.height < -30 { expanded = true } else if v.translation.height > 30 { expanded = false } }
    })
  }

  private var cityName: String {
    destinationPacks.first.map { "\($0.countryName) · " } ?? ""
  }

  @ViewBuilder private var statusChip: some View {
    let saved = !packs.isEmpty
    HStack(spacing: 4) {
      Image(systemName: saved ? "checkmark" : "exclamationmark").font(.system(size: 10, weight: .bold))
      Text(offline ? (saved ? "Saved" : "Not saved") : (saved ? "Offline ready" : "Not saved")).mta(.label)
    }
    .foregroundStyle(saved ? MTA.onColor : MTA.onNotice)
    .padding(.horizontal, 10).padding(.vertical, 5)
    .background(saved ? MTA.onTrack : MTA.obstacle, in: .rect(cornerRadius: 12))
  }

  @ViewBuilder private var emptyActions: some View {
    if let busy {
      HStack(spacing: 10) { ProgressView(); Text(busy).mta(.body1).foregroundStyle(MTA.text2) }
    } else if items.isEmpty {
      Text("Your hotel and plans appear here once your trip is set up.").mta(.body2).foregroundStyle(MTA.text2)
      Button { router.tab = .prepare } label: { Label("Prepare my trip", systemImage: "arrow.right").labelStyle(TrailingIcon()) }
        .buttonStyle(.mtaPrimary)
    } else {
      Button("Find my places on the map") { Task { await locate() } }.buttonStyle(.mtaPrimary).disabled(!net.isOnline)
      if !net.isOnline { Text("Needs Wi-Fi. Your GPS position still works offline.").mta(.body2).foregroundStyle(MTA.text2) }
    }
  }

  @ViewBuilder private var downloadActions: some View {
    if let busy {
      HStack(spacing: 10) { ProgressView(); Text(busy).mta(.body2).foregroundStyle(MTA.text2) }
    } else if packs.isEmpty {
      Button("Download map for offline") { Task { await download() } }.buttonStyle(.mtaPrimary).disabled(!net.isOnline)
    } else if net.isOnline {
      Button("Update offline map") { Task { await locate(); await download() } }.buttonStyle(.mtaSecondary(height: 44))
    }
  }

  // MARK: - Place row (distance computed from saved coordinates)

  private func placeRow(_ p: Place) -> some View {
    let fromHotel = hotel.flatMap { h in h === p ? nil : PlaceFacts.meters(h.latitude, h.longitude, p.latitude, p.longitude) }
    let fromYou = location.location.map { PlaceFacts.meters($0.coordinate.latitude, $0.coordinate.longitude, p.latitude, p.longitude) }
    let meters = fromYou ?? fromHotel
    let taxi = (meters ?? 0) >= 1500
    return Button { selected = p.name; focus(p) } label: {
      HStack(spacing: 14) {
        PinBullet(place: p, size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(p.name).mta(.body1).foregroundStyle(MTA.text).lineLimit(1)
          if let meters {
            Label("\(PlaceFacts.distance(meters)) \(fromYou == nil ? "from hotel" : "from you") · \(PlaceFacts.estimate(meters).replacingOccurrences(of: "about ", with: ""))",
                  systemImage: taxi ? "car.fill" : "figure.walk")
              .mta(.body2).foregroundStyle(MTA.text2)
          } else if p.kind == "hotel" {
            Text("Your hotel").mta(.body2).foregroundStyle(MTA.text2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if p.kind == "hotel", let item = items.first(where: { $0.title == p.name }), item.addressLocal != nil {
          Button { taxiItem = item } label: {
            Image(systemName: "car.fill").foregroundStyle(MTA.onColor).frame(width: 36, height: 36).background(MTA.accent, in: .circle)
          }
          .buttonStyle(.plain).accessibilityLabel("Show taxi card")
        }
      }
      .padding(.vertical, 8)
      .background(selected == p.name ? MTA.raised.opacity(0.6) : .clear, in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

  private func recenter() {
    if offline { return }
    if location.location != nil { camera = .userLocation(fallback: .automatic) }
    else if let hotel { focus(hotel) } else { camera = .automatic }
  }

  private func locate() async {
    busy = "Finding places on the map…"; error = nil
    defer { busy = nil }
    let added = await MapService.locate(items: items, plans: plans, context: context)
    if added.isEmpty && places.isEmpty { error = "Couldn't find your places. Check the hotel address in Trip." }
  }

  private func download() async {
    busy = "Saving the offline map…"; error = nil
    defer { busy = nil }
    do { _ = try await MapService.download(places: places, context: context); area = 0 } catch { self.error = error.localizedDescription }
  }

  private func focus(_ p: Place, meters: Double = 1500, animated: Bool = true) {
    guard !offline else { return }
    let region = MKCoordinateRegion(center: .init(latitude: p.latitude, longitude: p.longitude), latitudinalMeters: meters, longitudinalMeters: meters)
    if animated { withAnimation { camera = .region(region) } } else { camera = .region(region) }
  }
}

// MARK: - Pins & glass buttons

/// Hotel = New Blue with bed.double.fill; plans = inverse with mappin. White ring so they read on any map.
struct PinBullet: View {
  let place: Place
  var size: CGFloat = 30
  var body: some View {
    let hotel = place.kind == "hotel"
    Image(systemName: place.symbol)
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(hotel || place.kind == "airport" ? MTA.onColor : MTA.textInverse)
      .frame(width: size, height: size)
      .background(hotel || place.kind == "airport" ? MTA.accent : MTA.inverse, in: .circle)
      .overlay { Circle().strokeBorder(.white, lineWidth: 2.5).padding(-2.5) }
  }
}

/// Pin + name label (Live and Offline maps).
struct MapPin: View {
  let place: Place
  var selected = false
  var body: some View {
    HStack(spacing: 6) {
      PinBullet(place: place, size: place.kind == "hotel" ? 38 : 30)
      Text(place.name).mta(.label).foregroundStyle(MTA.text).lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(MTA.surface.opacity(0.92), in: .rect(cornerRadius: 10))
    }
    .scaleEffect(selected ? 1.15 : 1)
    .animation(.snappy, value: selected)
    .accessibilityElement(children: .combine)
  }
}

/// Round Liquid Glass button over the map.
struct GlassIcon: View {
  let systemName: String
  let color: Color
  let label: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: systemName).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
        .frame(width: 48, height: 48)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .accessibilityLabel(label)
  }
}

/// Saved snapshot with pins and the GPS dot drawn on top. No network needed.
/// Fills its container (aspect-fill), so it can run full screen.
struct OfflineMapView: View {
  let pack: MapPack
  let places: [Place]
  let here: CLLocation?
  let dark: Bool
  @Binding var selected: String?
  /// Height covered by the bottom sheet: the snapshot shifts up so its center stays visible.
  var bottomInset: CGFloat = 0

  var body: some View {
    GeometryReader { g in
      let side = max(g.size.width, g.size.height)
      let size = CGSize(width: side, height: side)
      ZStack(alignment: .topLeading) {
        if let data = (dark ? pack.nightImage : pack.dayImage) ?? pack.dayImage, let img = UIImage(data: data) {
          Image(uiImage: img).resizable().frame(width: side, height: side)
        } else {
          MTA.raised
        }
        ForEach(places.filter(inside)) { p in
          Button { selected = p.name } label: { MapPin(place: p, selected: selected == p.name).fixedSize() }
            .buttonStyle(.plain)
            .position(point(p.latitude, p.longitude, size))
        }
        if let here, MapProjection.contains(lat: here.coordinate.latitude, lon: here.coordinate.longitude, centerLat: pack.centerLatitude,
                                            centerLon: pack.centerLongitude, spanLat: pack.spanLatitude, spanLon: pack.spanLongitude) {
          ZStack {
            Circle().fill(MTA.accent.opacity(0.18)).frame(width: 56, height: 56)
            Circle().fill(MTA.accent).frame(width: 18, height: 18).overlay { Circle().strokeBorder(.white, lineWidth: 3) }
          }
          .position(point(here.coordinate.latitude, here.coordinate.longitude, size))
          .accessibilityLabel("You are here")
        }
      }
      .frame(width: side, height: side)
      .offset(x: (g.size.width - side) / 2, y: (g.size.height - side) / 2 - bottomInset / 2)
    }
    .clipped()
  }

  private func inside(_ p: Place) -> Bool {
    MapProjection.contains(lat: p.latitude, lon: p.longitude, centerLat: pack.centerLatitude, centerLon: pack.centerLongitude,
                           spanLat: pack.spanLatitude, spanLon: pack.spanLongitude)
  }

  private func point(_ lat: Double, _ lon: Double, _ size: CGSize) -> CGPoint {
    MapProjection.point(lat: lat, lon: lon, centerLat: pack.centerLatitude, centerLon: pack.centerLongitude,
                        spanLat: pack.spanLatitude, spanLon: pack.spanLongitude, size: size)
  }
}

extension Array {
  subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
