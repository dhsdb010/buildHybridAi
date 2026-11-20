import SwiftUI
import SwiftData

/// Help: bundled emergency numbers (never generated) and help phrases. Works offline.
struct HelpView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @Query private var cards: [EmergencyCard]
  @State private var emergency: EmergencyScreen?

  private var pack: DestinationPack? { packs.first }
  private var code: String? { pack?.countryCode ?? items.first { $0.kind == "hotel" }?.countryCode }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          MTALabel("\(pack?.countryName ?? code ?? "Local") · works offline")
          Text("Call for help").mta(.displayLarge).foregroundStyle(MTA.text)

          if let n = EmergencyNumbers.numbers(for: code) {
            HStack(spacing: MTA.gutter) {
              if let police = n["police"] { tile(police, "Police") }
              if let amb = n["ambulance"] { tile(amb, n["fire"] == amb ? "Fire · Ambulance" : "Ambulance") }
            }
            if let fire = n["fire"], fire != n["ambulance"] { tile(fire, "Fire") }
            if let tourist = n["tourist"] { tile(tourist, "Tourist police") }
          } else {
            NoticeCard(text: "No bundled numbers for this country yet. In most countries, 112 reaches emergency services.")
          }

          emergencyTile

          let phrases = (pack?.phrases ?? []).filter { ["help", "pharmacy"].contains($0.situation) }
          if !phrases.isEmpty {
            MTALabel("Say it")
            VStack(spacing: 0) {
              ForEach(phrases, id: \.self) { p in
                VStack(alignment: .leading, spacing: 2) {
                  Text(p.local).mta(.subheadMedium).foregroundStyle(MTA.text)
                  Text(p.english).mta(.body2).foregroundStyle(MTA.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle).frame(height: 1) }
              }
            }
          }
          NoticeCard(text: "Numbers are bundled in the app and checked. Phrases come from your Destination Pack, prepared by AI on Wi-Fi.")
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .navigationTitle("Help")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() } } }
      .fullScreenCover(item: $emergency) { EmergencyHost(screen: $0) }
    }
  }

  /// "My emergency card": shows the card, or starts the 5-question setup.
  private var emergencyTile: some View {
    let card = cards.first
    return Button { emergency = card == nil ? .setup : .card } label: {
      HStack(spacing: 14) {
        Image("StarOfLife").resizable().scaledToFit().frame(width: 54, height: 52).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          MTALabel("Show a doctor or pharmacist")
          Text("My emergency card").mta(.subheadMedium).foregroundStyle(MTA.text)
          Text(card == nil ? "Not set up yet · 5 quick questions" : "Allergies, medicines, blood type in \(pack?.languageName ?? "the local language")")
            .mta(.body2).foregroundStyle(MTA.text2)
          if card == nil {
            Text("Set it up").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
              .padding(.horizontal, 14).padding(.vertical, 8).background(MTA.emergency, in: .capsule).padding(.top, 2)
          }
        }
        Spacer(minLength: 0)
        if card != nil { Image(systemName: "chevron.right").foregroundStyle(MTA.text2) }
      }
      .padding(16)
      .background(MTA.surface, in: .rect(cornerRadius: 20))
      .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.gray.opacity(0.35), lineWidth: 1.5) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(card == nil ? "Set up my emergency card" : "Show my emergency card")
  }

  /// Red tile spanning 2 grid columns; tap to call.
  private func tile(_ number: String, _ label: String) -> some View {
    Button { if let url = URL(string: "tel:\(number)") { openURL(url) } } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(number).mta(.displayLarge).monospacedDigit()
        Text(label).mta(.label)
        Label("Tap to call", systemImage: "phone.fill").mta(.body2)
      }
      .foregroundStyle(MTA.onColor)
      .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
      .padding(.horizontal, 18)
      .background(MTA.urgent, in: .rect(cornerRadius: 20))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Call \(label), \(number)")
  }
}
