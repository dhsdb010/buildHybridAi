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

/// Black full-screen card with a Close button and a Flip mode for the local's reply.
private struct CardScaffold<Content: View>: View {
  let languageCode: String?
  let pack: DestinationPack?
  @ViewBuilder var content: Content

  @Environment(\.dismiss) private var dismiss
  @Environment(AIService.self) private var ai
  @State private var flipped = false
  @State private var replyText = ""
  @State private var reply: TranslationEntry?
  @State private var working = false
  @State private var error: String?
  @FocusState private var focused: Bool

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if flipped { replyPane.rotationEffect(.degrees(180)) } else { mainPane }
    }
    .statusBarHidden()
    .animation(.spring(duration: 0.4), value: flipped)
    #if DEBUG
    .task {
      // Debug: `-replyText "…"` flips the first card shown and submits that reply (simulator can't type CJK).
      guard !Self.debugReplyUsed, let text = UserDefaults.standard.string(forKey: "replyText") else { return }
      Self.debugReplyUsed = true
      try? await Task.sleep(for: .seconds(2))
      flipped = true
      replyText = text
      try? await Task.sleep(for: .seconds(2))
      await sendReply()
    }
    #endif
  }

  #if DEBUG
  @MainActor private static var debugReplyUsed: Bool {
    get { DebugFlags.replyUsed }
    set { DebugFlags.replyUsed = newValue }
  }
  #endif

  private var mainPane: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Button("Close", systemImage: "xmark") { dismiss() }
          .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white.opacity(0.7))
        Spacer()
      }
      content
      if let reply {
        VStack(alignment: .leading, spacing: 6) {
          HStack { Text("They replied").font(.caption).foregroundStyle(.white.opacity(0.6)); SourceBadge(entry: reply, onDark: true); if reply.isDraft { DraftChip() } }
          Text(reply.translation).font(.title2.bold()).foregroundStyle(.green)
            .fixedSize(horizontal: false, vertical: true)
          Text(reply.sourceText).font(.callout).foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
      }
      Spacer()
      Button {
        reply = nil; replyText = ""; flipped = true
      } label: {
        Label("Let them reply", systemImage: "arrow.2.squarepath").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black).controlSize(.large)
    }
    .padding(24)
  }

  /// Shown upside-down so the person across the counter can read and type.
  private var replyPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(ReplyPrompt.text(for: languageCode)).font(.title.bold()).foregroundStyle(.yellow)
      TextField("", text: $replyText, axis: .vertical)
        .font(.title2).foregroundStyle(.white)
        .padding().background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
        .lineLimit(3...6).focused($focused)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Button("✕") { flipped = false }.buttonStyle(.bordered).tint(.white).controlSize(.large)
        Button {
          Task { await sendReply() }
        } label: {
          (working ? AnyView(ProgressView()) : AnyView(Text("OK  ✓").bold())).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black).controlSize(.large)
        .disabled(replyText.nilIfEmpty == nil || working)
      }
      Spacer()
    }
    .padding(24)
    .onAppear { focused = true }
  }

  private func sendReply() async {
    guard let text = replyText.nilIfEmpty else { return }
    working = true; error = nil
    defer { working = false }
    do {
      reply = try await ai.translate(text, direction: "in", pack: pack).0
      focused = false
      flipped = false
    } catch {
      self.error = error.localizedDescription
    }
  }
}

/// Hotel Big-Card: the address in local script, for a taxi driver.
struct BigCardView: View {
  let item: VaultItem
  let pack: DestinationPack?

  var body: some View {
    CardScaffold(languageCode: pack?.languageCode, pack: pack) {
      if let taxiLine = pack?.taxiLine {
        Text(taxiLine).font(.title2.bold()).foregroundStyle(.yellow)
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
    }
  }
}

/// A translation shown big for a local person to read.
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
      if !entry.romanization.isEmpty {
        Text(entry.romanization).font(.title3).foregroundStyle(.white.opacity(0.7))
      }
      Text(entry.sourceText).font(.callout).foregroundStyle(.white.opacity(0.6))
      if !entry.note.isEmpty {
        Label(entry.note, systemImage: "info.circle").font(.caption).foregroundStyle(.white.opacity(0.5))
      }
    }
  }
}

#if DEBUG
@MainActor enum DebugFlags { static var replyUsed = false }
#endif
