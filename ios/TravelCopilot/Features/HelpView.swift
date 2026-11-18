import SwiftUI
import SwiftData

/// Help: bundled emergency numbers (never generated) and help phrases. Works offline.
struct HelpView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]

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
    }
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
