import SwiftUI
import SwiftData
import MapKit

/// Trip map. Live Apple Maps when online; the saved snapshot + GPS dot when offline.
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

  private var hotel: Place? { places.first { $0.kind == "hotel" } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            MTALabel(statusLine)
            Spacer()
            ConnectionChip()
          }
          MTASegmented(options: ["Live map", "Offline map"], selection: $mode)
          mapCard
          if mode == 1, packs.count > 1 {
            HStack(spacing: 8) {
              ForEach(packs.indices, id: \.self) { i in
                Button { area = i } label: {
                  Chip(text: packs[i].name, systemImage: i == area ? "checkmark" : nil, color: i == area ? MTA.accent : MTA.text2)
                }
                .buttonStyle(.plain)
              }
            }
          }
          downloadSection
          if !places.isEmpty {
            MTALabel(hotel == nil ? "Places" : "Places · from your hotel")
            VStack(spacing: 0) { ForEach(places) { placeRow($0) } }
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) {
        if !places.isEmpty {
          AskBar(placeholder: "How far is it from my hotel?") { router.ask = AskRequest() }
            .padding(.horizontal, MTA.margin).padding(.bottom, 8)
        }
      }
      .navigationTitle("Map")
      .navigationBarTitleDisplayMode(.inline)
      .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: destinationPacks.first) }
      .onAppear {
        location.start()
        if !net.isOnline { mode = 1 }
        #if DEBUG
          if UserDefaults.standard.string(forKey: "mapMode") == "offline" { mode = 1 }
        #endif
      }
      .onChange(of: net.isOnline) { _, online in if !online { mode = 1 } }
    }
  }

  // MARK: - Map card

  @ViewBuilder
  private var mapCard: some View {
    Group {
      if mode == 0 && net.isOnline {
        Map(position: $camera, selection: $selected) {
          ForEach(places) { p in
            Annotation(p.name, coordinate: .init(latitude: p.latitude, longitude: p.longitude)) {
              TripBullet(systemName: p.symbol, status: status(p), size: selected == p.name ? 36 : 28)
            }
            .tag(p.name)
          }
          UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .hotel, .pharmacy, .hospital, .police])))
      } else if let pack = packs[safe: area] {
        OfflineMapView(pack: pack, places: places, here: location.location, dark: scheme == .dark, selected: $selected) { status($0) }
      } else {
        VStack(spacing: 10) {
          Image(systemName: "icloud.slash").font(.system(size: 34, weight: .semibold)).foregroundStyle(MTA.text2)
          Text(net.isOnline ? "No offline map yet" : "Offline — no map saved").mta(.subheadNormal).foregroundStyle(MTA.text)
          Text("Download it on Wi-Fi so your hotel and places stay on the map with no signal.")
            .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(MTA.raised)
      }
    }
    .frame(height: 380)
    .clipShape(.rect(cornerRadius: 20))
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.border, lineWidth: 2) }
  }

  @ViewBuilder
  private var downloadSection: some View {
    if let busy {
      HStack(spacing: 10) { ProgressView(); Text(busy).mta(.body1).foregroundStyle(MTA.text2) }
    } else if places.isEmpty {
      if items.isEmpty {
        NoticeCard(text: "Add your bookings in Prepare first — the map is built from them.")
      } else {
        Button("Find my places on the map") { Task { await locate() } }.buttonStyle(.mtaPrimary).disabled(!net.isOnline)
      }
    } else if packs.isEmpty {
      Button("Download map for offline") { Task { await download() } }.buttonStyle(.mtaPrimary).disabled(!net.isOnline)
    } else {
      Button("Update offline map") { Task { await locate(); await download() } }
        .buttonStyle(.mtaSecondary(height: 44)).disabled(!net.isOnline)
    }
    if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
    if !net.isOnline && busy == nil && (places.isEmpty || packs.isEmpty) {
      NoticeCard(text: "Needs Wi-Fi. Your GPS position still works offline.")
    }
  }

  // MARK: - Place row (distance computed from saved coordinates)

  private func placeRow(_ p: Place) -> some View {
    let fromHotel = hotel.flatMap { h in h === p ? nil : PlaceFacts.meters(h.latitude, h.longitude, p.latitude, p.longitude) }
    let fromYou = location.location.map { PlaceFacts.meters($0.coordinate.latitude, $0.coordinate.longitude, p.latitude, p.longitude) }
    return Button { selected = p.name; focus(p) } label: {
      HStack(spacing: 14) {
        TripBullet(systemName: p.symbol, status: status(p), size: 32)
        VStack(alignment: .leading, spacing: 2) {
          Text(p.name).mta(.subheadNormal).foregroundStyle(MTA.text).lineLimit(2)
          if let m = fromHotel {
            Text("\(PlaceFacts.distance(m)) from hotel · \(PlaceFacts.estimate(m))").mta(.body2).foregroundStyle(MTA.text2)
          } else if p.kind == "hotel" {
            Text("Your hotel").mta(.body2).foregroundStyle(MTA.text2)
          }
          if let you = fromYou { MTALabel("\(PlaceFacts.distance(you)) from you", color: MTA.accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if p.kind == "hotel", let item = items.first(where: { $0.title == p.name }), item.addressLocal != nil {
          Button { taxiItem = item } label: { Image(systemName: "car.fill").foregroundStyle(MTA.onColor).frame(width: 36, height: 36).background(MTA.accent, in: .circle) }
            .buttonStyle(.plain).accessibilityLabel("Show taxi card")
        }
      }
      .padding(.vertical, 12)
      .background(selected == p.name ? MTA.raised.opacity(0.6) : .clear)
      .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

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

  private func focus(_ p: Place) {
    camera = .region(MKCoordinateRegion(center: .init(latitude: p.latitude, longitude: p.longitude), latitudinalMeters: 1500, longitudinalMeters: 1500))
  }

  private func status(_ p: Place) -> MTAStatus { p.kind == "plan" ? .onTrack : .accent }

  private var statusLine: String {
    if let pack = packs.first { return "Offline map saved \(pack.createdAt.formatted(.dateTime.month(.abbreviated).day()))" }
    return places.isEmpty ? "No places yet" : "\(places.count) places · not saved offline"
  }
}

/// Saved snapshot with pins and the GPS dot drawn on top. No network needed.
struct OfflineMapView: View {
  let pack: MapPack
  let places: [Place]
  let here: CLLocation?
  let dark: Bool
  @Binding var selected: String?
  let status: (Place) -> MTAStatus

  var body: some View {
    GeometryReader { g in
      let side = max(g.size.width, g.size.height)
      let size = CGSize(width: side, height: side)
      ZStack(alignment: .topLeading) {
        if let data = (dark ? pack.nightImage : pack.dayImage) ?? pack.dayImage, let img = UIImage(data: data) {
          Image(uiImage: img).resizable().frame(width: side, height: side)
        }
        ForEach(places.filter(inside)) { p in
          Button { selected = p.name } label: {
            TripBullet(systemName: p.symbol, status: status(p), size: selected == p.name ? 34 : 26)
          }
          .buttonStyle(.plain)
          .position(point(p.latitude, p.longitude, size))
          .accessibilityLabel(p.name)
        }
        if let here, MapProjection.contains(lat: here.coordinate.latitude, lon: here.coordinate.longitude, centerLat: pack.centerLatitude,
                                            centerLon: pack.centerLongitude, spanLat: pack.spanLatitude, spanLon: pack.spanLongitude) {
          Circle().fill(MTA.accent).frame(width: 16, height: 16)
            .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
            .shadow(radius: 3)
            .position(point(here.coordinate.latitude, here.coordinate.longitude, size))
            .accessibilityLabel("You are here")
        }
      }
      .frame(width: side, height: side)
      .offset(x: (g.size.width - side) / 2, y: (g.size.height - side) / 2)
      .overlay(alignment: .bottomLeading) {
        Chip(text: "Offline · \(pack.name)", systemImage: "icloud.slash", color: MTA.text)
          .background(MTA.surface.opacity(0.85), in: .capsule).padding(12)
      }
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
