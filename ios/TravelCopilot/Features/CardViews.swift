import SwiftUI

/// "📱 On-device · 110 ms" / "☁️ Cloud · 640 ms"
struct SourceBadge: View {
  let source: InferenceSource
  let latencyMs: Int
  var onDark = false

  init(_ meta: AIMeta, onDark: Bool = false) {
    self.source = meta.source
    self.latencyMs = meta.latencyMs
    self.onDark = onDark
  }

  init(entry: TranslationEntry, onDark: Bool = false) {
    self.source = entry.source == "onDevice" ? .onDevice : .inCloud
    self.latencyMs = entry.latencyMs
    self.onDark = onDark
  }

  var body: some View {
    Label("\(source == .onDevice ? "On-device" : "Cloud · Gemini") · \(SourceChip.format(latencyMs))",
          systemImage: source == .onDevice ? "iphone" : "icloud")
      .font(.caption2.weight(.semibold).monospacedDigit())
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(source == .onDevice ? MTA.onTrack.opacity(0.25) : MTA.accent.opacity(0.3), in: .capsule)
      .foregroundStyle(onDark ? .white : .primary)
  }
}

struct DraftChip: View {
  var body: some View {
    Label("Draft", systemImage: "pencil.and.outline")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(Color.orange.opacity(0.25), in: .capsule)
      .foregroundStyle(.orange)
      .accessibilityLabel("Draft: will be polished in the cloud when back on Wi-Fi")
  }
}

/// Black full-screen card with a Close button and a reply flow:
/// main card → "turn the phone around" (traveler) → reply screen in the local language (local person).
private struct CardScaffold<Content: View>: View {
  let languageCode: String?
  let pack: DestinationPack?
  /// Who gets the phone: "the driver" on the taxi card, "them" elsewhere.
  var audience = "them"
  @ViewBuilder var content: Content

  enum Stage { case main, handOver, reply }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(AIService.self) private var ai
  @State private var stage: Stage = .main
  @State private var replyText = ""
  @State private var reply: TranslationEntry?
  @State private var working = false
  @State private var error: String?

  private var language: String { pack?.languageName ?? Keyboards.name(for: languageCode) }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      switch stage {
      case .main: mainPane
      case .handOver: handOverPane.transition(.move(edge: .trailing))
      case .reply: replyPane.transition(.opacity)
      }
    }
    .statusBarHidden()
    .animation(.snappy, value: stage)
    .onDisappear { Speaker.shared.stop() }
    #if DEBUG
    .task {
      // Debug: `-replyText "…"` opens the reply screen and submits that reply (simulator can't type CJK).
      // `-replyStage handover` stops on the "turn the phone around" screen instead.
      if UserDefaults.standard.string(forKey: "replyStage") == "handover", !DebugFlags.replyUsed {
        DebugFlags.replyUsed = true
        try? await Task.sleep(for: .seconds(1)); stage = .handOver; return
      }
      if UserDefaults.standard.string(forKey: "replyStage") == "reply", !DebugFlags.replyUsed {
        DebugFlags.replyUsed = true
        try? await Task.sleep(for: .seconds(1)); stage = .reply; return
      }
      guard !DebugFlags.replyUsed, let text = UserDefaults.standard.string(forKey: "replyText") else { return }
      DebugFlags.replyUsed = true
      try? await Task.sleep(for: .seconds(2))
      stage = .reply
      replyText = text
      try? await Task.sleep(for: .seconds(2))
      await sendReply()
    }
    #endif
  }

  // MARK: Main card

  private var mainPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Button("Close", systemImage: "xmark") { dismiss() }
          .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white.opacity(0.7))
        Spacer()
      }
      .padding(.bottom, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let reply {
            VStack(alignment: .leading, spacing: 6) {
              HStack { Text("They replied").font(.caption).foregroundStyle(.white.opacity(0.6)); SourceBadge(entry: reply, onDark: true); if reply.isDraft { DraftChip() } }
              Text(reply.translation).font(.title2.bold()).foregroundStyle(MTA.onTrack)
                .fixedSize(horizontal: false, vertical: true)
              Text(reply.sourceText).font(.callout).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MTA.onTrack.opacity(0.18), in: .rect(cornerRadius: 12))
          }
          content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden)
      Button {
        reply = nil; replyText = ""; error = nil; Speaker.shared.stop(); stage = .handOver
      } label: {
        Label("Let them reply", systemImage: "arrow.2.squarepath").mta(.button1).frame(maxWidth: .infinity, minHeight: 52)
      }
      .buttonStyle(.plain).background(MTA.notice, in: .capsule).foregroundStyle(MTA.onNotice)
      .padding(.top, 12)
    }
    .padding(24)
  }

  // MARK: Hand-over (for the traveler)

  private var handOverPane: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Button("Back", systemImage: "chevron.left") { stage = .main }
          .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white.opacity(0.7))
        Spacer()
      }
      Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        .font(.system(size: 56, weight: .semibold)).foregroundStyle(MTA.notice)
      MTALabel("Step 1 · you", color: .white.opacity(0.6))
      Text("Turn the phone around").mta(.displayMedium).foregroundStyle(.white)
      Text("Hand it to \(audience). The next screen speaks \(language), so they can type their reply. You'll get it back in English.")
        .mta(.body1).foregroundStyle(.white.opacity(0.75))

      if Keyboards.has(languageCode) {
        Label("\(language) keyboard is ready", systemImage: "keyboard.badge.ellipsis")
          .mta(.body2).foregroundStyle(MTA.onTrack)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Label("Add the \(language) keyboard first", systemImage: "keyboard").mta(.subheadNormal)
          Text("So they can type in \(language):\nSettings › General › Keyboard › Keyboards › Add New Keyboard › \(language).\nIt works offline once added.")
            .mta(.body2)
          Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            .mta(.button2).padding(.horizontal, 14).padding(.vertical, 8)
            .background(MTA.onNotice, in: .capsule).foregroundStyle(MTA.notice)
        }
        .foregroundStyle(MTA.onNotice)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MTA.notice, in: .rect(cornerRadius: 12))
      }
      Spacer()
      Button { stage = .reply } label: {
        Label("Show the screen for \(audience)", systemImage: "arrow.right").labelStyle(TrailingIcon())
          .mta(.button1).frame(maxWidth: .infinity, minHeight: 52)
      }
      .buttonStyle(.plain).background(.white, in: .capsule).foregroundStyle(.black)
    }
    .padding(24)
  }

  // MARK: Reply (for the local person: the screen they read, in their language)

  private var replyPane: some View {
    let local = LocalReplyScreen.screen(for: languageCode)
    return VStack(alignment: .leading, spacing: 16) {
      HStack {
        // Small English line for the traveller, so they know what the other person sees.
        MTALabel("For \(audience) · in \(language)", color: .white.opacity(0.5))
        Spacer()
        Button("Back to my card", systemImage: "xmark") { stage = .main }
          .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white.opacity(0.7))
      }
      Image(systemName: "character.bubble.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(MTA.notice)
        .accessibilityHidden(true)
      Text(local.title).mta(.displayMedium).foregroundStyle(MTA.notice).fixedSize(horizontal: false, vertical: true)
      Text(local.body).mta(.body1).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
      LocalTextField(text: $replyText, languageCode: languageCode, placeholder: local.placeholder) { Task { await sendReply() } }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.notice.opacity(0.6), lineWidth: 2) }
      if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
      Button { Task { await sendReply() } } label: {
        Group {
          if working { ProgressView().tint(.black) } else {
            HStack(spacing: 8) {
              Image(systemName: "paperplane.fill")
              Text(local.send).mta(.button1)
              if local.send != "Send" { Text("· Send").mta(.button2).opacity(0.6) }
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
      }
      .buttonStyle(.plain).background(MTA.notice, in: .capsule).foregroundStyle(MTA.onNotice)
      .disabled(replyText.nilIfEmpty == nil || working)
      .opacity(replyText.nilIfEmpty == nil ? 0.5 : 1)
      .accessibilityLabel("\(local.send), Send")
      Text(local.handBack).mta(.body2).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .padding(24)
  }

  private func sendReply() async {
    guard let text = replyText.nilIfEmpty else { return }
    working = true; error = nil
    defer { working = false }
    do {
      reply = try await ai.translate(text, direction: "in", pack: pack).0
      stage = .main
    } catch {
      self.error = error.localizedDescription
    }
  }
}

/// "How to say it": the local text, its pronunciation in English letters, the meaning, and a play button.
private struct SayItBlock: View {
  let label: String
  let local: String
  let meaning: String?
  let languageCode: String?
  let id: String

  var body: some View {
    let romaji = Romanizer.latin(local, languageCode: languageCode)
    VStack(alignment: .leading, spacing: 6) {
      MTALabel(label, color: .white.opacity(0.55))
      if !romaji.isEmpty { Text(romaji).mta(.subheadNormal).foregroundStyle(.white) }
      if let meaning { Text("“\(meaning)”").mta(.body2).foregroundStyle(.white.opacity(0.6)) }
      HStack(spacing: 18) {
        SpeakButton(text: local, languageCode: languageCode, id: id, label: "Play")
        SpeakButton(text: local, languageCode: languageCode, id: id + "-slow", label: "Slowly", slow: true)
      }
      .padding(.top, 4)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
  }
}

/// Hotel Big-Card: the address in local script, for a taxi driver — plus how to say it.
struct BigCardView: View {
  let item: VaultItem
  let pack: DestinationPack?

  var body: some View {
    CardScaffold(languageCode: pack?.languageCode, pack: pack, audience: "the driver") {
      if let taxiLine = pack?.taxiLine {
        Text(taxiLine).font(.title2.bold()).foregroundStyle(MTA.notice)
      }
      Text(item.addressLocal ?? item.address ?? "")
        .font(.system(size: 44, weight: .heavy))
        .minimumScaleFactor(0.3)
        .foregroundStyle(.white)
      Text(item.title).font(.title3).foregroundStyle(.white.opacity(0.8))
      if let address = item.address {
        Text(address).font(.callout).foregroundStyle(.white.opacity(0.6))
      }
      if item.addressLocalIsAIGenerated {
        Label("Address translated by AI", systemImage: "sparkles")
          .font(.caption).foregroundStyle(.white.opacity(0.5))
      }
      if let local = item.addressLocal {
        let code = pack?.languageCode ?? item.countryCode.map { $0 == "JP" ? "ja" : $0.lowercased() }
        if let taxiLine = pack?.taxiLine {
          SayItBlock(label: "Say this · \(pack?.languageName ?? "local")", local: taxiLine,
                     meaning: "Please take me to this address.", languageCode: code, id: "taxi")
        }
        SayItBlock(label: "The address", local: local, meaning: nil, languageCode: code, id: "address")
        SpeakButton(text: [pack?.taxiLine, local].compactMap { $0 }.joined(separator: "。"),
                    languageCode: code, id: "driver", label: "Play it all for the driver")
      }
    }
  }
}

/// A translation shown big for a local person to read — with pronunciation and playback.
struct TranslationCardView: View {
  let entry: TranslationEntry
  let pack: DestinationPack?

  var body: some View {
    CardScaffold(languageCode: pack?.languageCode, pack: pack) {
      HStack { SourceBadge(entry: entry, onDark: true); if entry.isDraft { DraftChip() } }
      Text(entry.translation)
        .font(.system(size: 40, weight: .heavy))
        .minimumScaleFactor(0.3)
        .foregroundStyle(.white)
      SayItBlock(label: "Say it", local: entry.translation, meaning: entry.sourceText,
                 languageCode: pack?.languageCode ?? entry.languageCode, id: "translation")
      if !entry.note.isEmpty {
        Label(entry.note, systemImage: "info.circle").font(.caption).foregroundStyle(.white.opacity(0.5))
      }
    }
  }
}

#if DEBUG
@MainActor enum DebugFlags { static var replyUsed = false }
#endif
