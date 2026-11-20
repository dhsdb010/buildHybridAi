import SwiftData
import SwiftUI

/// The emergency card a traveler shows a doctor or pharmacist (Figma: Emergency info card · flow, B7/B8).
/// Full screen: blue band from the top, grabber + swipe down to close (no ✕), plain black-and-white form,
/// local language first. "Show English" flips it; Call dials the local ambulance number.
struct EmergencyCardView: View {
  let card: EmergencyCard
  let pack: DestinationPack?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var localFirst: Bool
  @State private var drag: CGFloat = 0

  init(card: EmergencyCard, pack: DestinationPack?, english: Bool = false) {
    self.card = card
    self.pack = pack
    _localFirst = State(initialValue: !english)
  }

  private var language: String { pack?.languageCode ?? card.translationLanguage }
  private var hasLocal: Bool { EmergencyText.labels(for: language) != nil }
  private var showLocal: Bool { localFirst && hasLocal }
  private var ambulance: String {
    let n = EmergencyNumbers.numbers(for: pack?.countryCode)
    return n?["ambulance"] ?? n?["fire"] ?? "112"
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(card.rows(language: language, localFirst: showLocal).enumerated()), id: \.offset) { _, r in row(r) }
        }
        .padding(.horizontal, 16).padding(.top, 8)
      }
      .scrollIndicators(.hidden)
      buttons
    }
    .background(Color.white)
    .environment(\.colorScheme, .light)   // a printed-card look, also in Dark Mode
    .offset(y: max(0, drag))
    .gesture(
      DragGesture(minimumDistance: 12)
        .onChanged { drag = $0.translation.height }
        .onEnded { v in
          if v.translation.height > 120 || v.predictedEndTranslation.height > 260 { dismiss() }
          else { withAnimation(.snappy) { drag = 0 } }
        }
    )
    .statusBarHidden(false)
    .accessibilityAction(.escape) { dismiss() }
  }

  // MARK: - Pieces

  private var header: some View {
    let en = EmergencyText.english
    let loc = EmergencyText.labels(for: language)
    return VStack(spacing: 0) {
      Capsule().fill(.white.opacity(0.6)).frame(width: 40, height: 5).padding(.top, 8)
        .accessibilityLabel("Swipe down to close")
      HStack(spacing: 16) {
        Image("StarOfLifeOnColor").resizable().scaledToFit().frame(width: 80, height: 78)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(showLocal ? loc!.title : en.title)
            .font(.system(size: showLocal ? 26 : 21, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
          if let loc { Text(showLocal ? en.title : loc.title).font(.system(size: 16, weight: .semibold)) }
          Text("Speaks \(card.speaks)").font(.system(size: 13))
        }
        .foregroundStyle(.white)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 22)
    }
    .frame(maxWidth: .infinity)
    .background(MTA.emergency.ignoresSafeArea(edges: .top))
    .accessibilityElement(children: .combine)
  }

  private func row(_ r: EmergencyRow) -> some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .leading, spacing: 1) {
        Text(r.label).font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
        Text(r.labelOther).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.37))
      }
      .frame(width: 100, alignment: .leading).padding(.trailing, 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(r.value).font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
          .fixedSize(horizontal: false, vertical: true)
        if let o = r.valueOther {
          Text(o).font(.system(size: 13)).foregroundStyle(Color(white: 0.37)).fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.leading, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) { Rectangle().fill(Color(white: 0.8)).frame(width: 1) }
    }
    .padding(.vertical, 11)
    .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.8)).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }

  private var buttons: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button { if let u = URL(string: "tel:\(ambulance)") { openURL(u) } } label: {
          Text("Call \(ambulance)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54).background(MTA.emergency, in: .capsule)
        }
        if hasLocal {
          Button { withAnimation(.snappy) { localFirst.toggle() } } label: {
            Text(showLocal ? "Show English" : (localName ?? "Show local language"))
              .font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
              .frame(maxWidth: .infinity, minHeight: 54)
              .overlay { Capsule().strokeBorder(.black, lineWidth: 1.5) }
          }
        }
      }
      .buttonStyle(.plain)
      Text("Swipe down to close").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.37))
    }
    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
  }

  /// "日本語で表示" etc.: the flip button speaks the local language.
  private var localName: String? {
    ["ja": "日本語で表示", "ko": "한국어로 보기", "zh": "显示中文"][String(language.prefix(2))]
  }
}

enum EmergencyScreen: String, Identifiable {
  case setup, card, english
  var id: String { rawValue }
}

/// Shows the card if there is one (else the setup quiz); after setup, goes straight to the card.
struct EmergencyHost: View {
  @State var screen: EmergencyScreen
  @Query private var cards: [EmergencyCard]
  @Query private var packs: [DestinationPack]
  @Environment(\.modelContext) private var context
  @Environment(AIService.self) private var ai

  var body: some View {
    Group {
      if screen == .setup || cards.first == nil {
        EmergencySetupView { _ in withAnimation(.snappy) { screen = .card } }
      } else if let card = cards.first {
        EmergencyCardView(card: card, pack: packs.first, english: screen == .english)
      }
    }
    #if DEBUG
    .task {
      // `-emergencySample`: fill a sample card (as in Figma) and translate it, for simulator checks.
      guard ProcessInfo.processInfo.arguments.contains("-emergencySample") else { return }
      for c in cards { context.delete(c) }
      let c = EmergencyCard()
      c.bloodType = "A+"
      c.medicines = [EmergencyMedicine(name: "Ibuprofen 200 mg", schedule: "twice a day")]
      c.allergies = ["Penicillin", "Peanuts"]; c.conditions = ["Asthma"]
      c.contactName = "Jamie Lee"; c.contactPhone = "+1 415 555 0134"; c.contactRelation = "Partner"
      context.insert(c); try? context.save()
      _ = await EmergencyTranslator.translate(c, to: packs.first?.languageCode ?? "ja", languageName: packs.first?.languageName ?? "Japanese", ai: ai)
      try? context.save()
    }
    #endif
  }
}
