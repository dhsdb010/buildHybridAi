import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Vision

/// Blue, the trip chat (Figma: App Screens → "Blue · Chat flow").
/// Laid out like Messages: your questions on the right in blue, Blue's answers on the left with its logo.
/// Ask mode: the on-device model only picks a booking field; the answer is that stored value.
/// The あ button switches to Say in <language> (context translation).
/// The conversation is saved (`ChatMessage`), so it's still there when you open Blue again.
struct AskView: View {
  let request: AskRequest
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @Query(sort: \Place.createdAt) private var places: [Place]
  @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
  @Query private var translations: [TranslationEntry]
  @Environment(LocationService.self) private var location
  @Environment(AppRouter.self) private var router
  @State private var sayMode = false
  @State private var question = ""
  @State private var asking = false
  @State private var confirmClear = false
  @State private var taxiItem: VaultItem?
  @State private var translationCard: TranslationEntry?
  @FocusState private var focused: Bool
  @State private var speech = SpeechInput()
  @State private var showAdd = false
  @State private var showCamera = false
  @State private var showFiles = false
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var talking = false
  @State private var talkPhase: TalkSheet.Phase = .listening
  @State private var heard = ""
  @State private var spoken = ""

  private var pack: DestinationPack? { packs.first }
  private var language: String { pack?.languageName ?? "local language" }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            stamp(messages.first?.createdAt ?? .now)
            BlueRow {
              Text("Hi, I'm Blue 👋").mta(.subheadNormal)
              Text("I answer from your saved bookings, right on your phone, even with no signal. What do you need?")
                .mta(.body1)
            }
            if messages.isEmpty { SuggestionList(list: suggestions(followUp: false), send: send) }
            ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
              // A time line like Messages when an hour or more passed since the last message.
              if i > 0, m.createdAt.timeIntervalSince(messages[i - 1].createdAt) > 3600 { stamp(m.createdAt) }
              message(m, isLast: i == messages.count - 1)
            }
            if asking { BlueRow { TypingDots() }.id("typing") }
            Color.clear.frame(height: 1).id("bottom")
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom)
        .onChange(of: messages.count) { withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } }
        .onChange(of: asking) { withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } }
      }
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) { inputBar }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() } }
        ToolbarItem(placement: .principal) {
          VStack(spacing: 2) {
            BlueAvatar(size: 32)
            Text("Blue").font(.system(size: 12, weight: .semibold)).foregroundStyle(MTA.text)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Blue, your trip assistant")
        }
        if !messages.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("New chat", systemImage: "square.and.pencil") { confirmClear = true }
          }
        }
      }
      .confirmationDialog("Start a new chat?", isPresented: $confirmClear, titleVisibility: .visible) {
        Button("Clear chat history", role: .destructive) { clear() }
      } message: {
        Text("This removes the messages with Blue. Your bookings and saved phrases stay.")
      }
      .fullScreenCover(item: $taxiItem) { BigCardView(item: $0, pack: pack) }
      .overlay(alignment: .bottom) {
        if showAdd {
          ZStack(alignment: .bottom) {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { showAdd = false }
            AddToChatSheet(photos: $photoItems,
                           onCamera: { showAdd = false; showCamera = true },
                           onFiles: { showAdd = false; showFiles = true },
                           onClose: { showAdd = false })
              .transition(.move(edge: .bottom))
          }
          .ignoresSafeArea(edges: .bottom)
        }
      }
      .animation(.snappy, value: showAdd)
      .onChange(of: photoItems) {
        let items = photoItems
        guard let first = items.first else { return }
        photoItems = []
        Task {
          if let data = try? await first.loadTransferable(type: Data.self), let img = UIImage(data: data) { await addImage(img) }
        }
      }
      .fullScreenCover(isPresented: $showCamera) {
        CameraPicker { img in Task { await addImage(img) } }.ignoresSafeArea()
      }
      .fileImporter(isPresented: $showFiles, allowedContentTypes: FileReader.types, allowsMultipleSelection: false) { result in
        if case let .success(urls) = result, let url = urls.first { Task { await addFile(url) } }
      }
      .sheet(isPresented: $talking, onDismiss: { stopTalking() }) {
        TalkSheet(phase: $talkPhase, heard: heard, reply: spoken) { talking = false }
      }
      .fullScreenCover(item: $translationCard) { TranslationCardView(entry: $0, pack: pack) }
    }
    .task {
      sayMode = request.mode == 1
      if request.autoSubmit, let q = request.text.nilIfEmpty { send(q) }
      else { question = request.text; if !request.text.isEmpty { focused = true } }
    }
  }

  private func stamp(_ date: Date) -> some View {
    Text(date.formatted(.dateTime.weekday(.wide).hour().minute()))
      .mta(.label).foregroundStyle(MTA.text2).frame(maxWidth: .infinity)
  }

  // MARK: - Input: the same bar as the planner, with あ (Say in <language>) on its left

  private var inputBar: some View {
    PlanComposer(text: $question, placeholder: sayMode ? "Say in \(language)" : "Message Blue",
                 focused: $focused, canSend: !asking, speech: speech,
                 onSend: { send(question) },
                 onPlus: { focused = false; showAdd = true },
                 onTalk: { startTalking() },
                 leading: AnyView(sayButton))
      .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
      .background(MTA.surface)
  }

  private var sayButton: some View {
    Button { withAnimation(.snappy) { sayMode.toggle() } } label: {
      Text("あ").font(.system(size: 19, weight: .medium))
        .foregroundStyle(sayMode ? MTA.onColor : MTA.text)
        .frame(width: 50, height: 50)
        .background(sayMode ? MTA.accent : MTA.raised, in: .circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(sayMode ? "Say in \(language) is on" : "Say in \(language)")
  }

  // MARK: - + : photos (text read on this iPhone), camera, files

  private func addImage(_ image: UIImage) async {
    guard let cg = (image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)) ?? image).cgImage else { return }
    let lines = await Task.detached(priority: .userInitiated) { TextInImage.read(cg) }.value
    if lines.isEmpty {
      question = "What can you tell me about this photo?"
    } else {
      question = "What does this say? " + lines.prefix(6).joined(separator: " ")
    }
    focused = true
  }

  private func addFile(_ url: URL) async {
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { await addImage(img) }
      return
    }
    guard let (text, _) = FileReader.read(url), !text.isEmpty else {
      context.insert(ChatMessage(role: "blue", kind: "other", text: "I couldn't read any text in that file. Try a PDF or a text document."))
      return
    }
    context.insert(ChatMessage(role: "you", kind: "text", text: "📄 " + url.lastPathComponent))
    if FileReader.looksLikeBooking(text) {
      asking = true
      defer { asking = false }
      do {
        let (found, added) = try await PrepareService.saveBookings(from: text, ai: ai)
        context.insert(ChatMessage(role: "blue", kind: "other", text: found.isEmpty ? "I couldn't find a booking in it."
          : added == 0 ? "Those bookings are already saved. Ask me anything about them."
          : "Saved \(added) booking\(added == 1 ? "" : "s"). Ask me anything about \(added == 1 ? "it" : "them"), even offline."))
      } catch {
        context.insert(ChatMessage(role: "blue", kind: "error", text: error.localizedDescription))
      }
    } else {
      question = "About this file: " + String(text.prefix(400))
      focused = true
    }
    try? context.save()
  }

  // MARK: - Talk: you speak, Blue answers out loud, and listens again

  private func startTalking() {
    focused = false; heard = ""; spoken = ""
    talking = true
    Task { await talkLoop() }
  }

  private func stopTalking() {
    talking = false
    speech.stop()
    Speaker.shared.stop()
  }

  private func talkLoop() async {
    while talking {
      talkPhase = .listening; heard = ""
      let said: String = await withCheckedContinuation { c in
        Task { await speech.listenOnce(onText: { heard = $0 }, onDone: { c.resume(returning: $0) }) }
      }
      guard talking else { return }
      if speech.error != nil { talking = false; return }
      let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      talkPhase = .thinking
      let before = messages.count
      send(text)
      try? await Task.sleep(for: .milliseconds(300))
      while (asking || messages.count <= before) && talking { try? await Task.sleep(for: .milliseconds(200)) }
      guard talking, let reply = messages.last(where: { $0.role == "blue" }) else { return }
      // Say mode: speak the translation in the local language; otherwise Blue's answer in English.
      let local = reply.kind == "translation" && !reply.value.isEmpty
      spoken = local ? reply.value : [reply.value, reply.text].filter { !$0.isEmpty }.joined(separator: ". ")
      talkPhase = .speaking
      Speaker.shared.toggle(spoken, languageCode: local ? pack?.languageCode : "en", id: "talk")
      while Speaker.shared.speakingID == "talk" && talking { try? await Task.sleep(for: .milliseconds(200)) }
    }
  }

  // MARK: - Messages (drawn from what was saved)

  @ViewBuilder
  private func message(_ m: ChatMessage, isLast: Bool) -> some View {
    if m.role == "you" {
      HStack {
        Spacer(minLength: 60)
        Text(m.text).mta(.body1).foregroundStyle(MTA.onColor)
          .padding(.horizontal, 14).padding(.vertical, 9)
          .background(MTA.accent, in: .rect(cornerRadius: 20))
      }
      .transition(.move(edge: .bottom).combined(with: .opacity))
    } else {
      BlueRow(caption: liveCaption(m), captionColor: captionColor(m)) {
        switch m.kind {
        case "vault", "place":
          Text(m.value).mta(m.value.count <= 12 ? .displayLarge : .subheadMedium).monospacedDigit()
            .lineLimit(4).minimumScaleFactor(0.6)
          if !m.subtitle.isEmpty { Text(m.subtitle).mta(.subheadNormal) }
          Text(m.text).mta(.body1)
          if !m.sourceTitle.isEmpty {
            BookingSource(title: m.sourceTitle, ref: m.sourceRef.nilIfEmpty, symbol: m.sourceSymbol)
          }
        case "translation":
          // Drawn from the live entry, so the bubble updates itself when the catch-up pass improves it.
          let e = entry(for: m.link)
          Text(e?.translation ?? m.value).mta(.subheadMedium).fixedSize(horizontal: false, vertical: true)
          let roman = e?.romanization ?? m.subtitle
          if !roman.isEmpty { Text(roman).mta(.body2).foregroundStyle(MTA.text2) }
          if let draft = e?.draftTranslation {
            Text(draft).mta(.body2).strikethrough().foregroundStyle(MTA.text2)
              .accessibilityLabel("Offline draft was: \(draft)")
          }
          if let what = e?.whatChanged {
            Label(what, systemImage: "sparkle").mta(.body2).foregroundStyle(MTA.accent)
          }
          if let why = e?.checkReason {
            VStack(alignment: .leading, spacing: 4) {
              MTALabel("Check this", color: MTA.urgent)
              Text("The cloud version changed something, so your draft is kept: \(why).").mta(.body2).foregroundStyle(MTA.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MTA.surface, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(MTA.urgent, lineWidth: 1.5) }
          }
          if !m.note.isEmpty { Label(m.note, systemImage: "info.circle").mta(.body2).foregroundStyle(MTA.text2) }
        case "cloud":
          Label("Cloud · Gemini", systemImage: "icloud").mta(.body2).fontWeight(.semibold).foregroundStyle(MTA.accent)
          Text(m.text).mta(.body1)
          if !m.note.isEmpty { Text("You asked this offline; answered when you were back online.").mta(.body2).foregroundStyle(MTA.text2) }
        case "waiting":
          Label("Waiting for a connection", systemImage: "icloud.slash").mta(.body2).fontWeight(.semibold).foregroundStyle(MTA.obstacle)
          Text(m.text).mta(.body1)
        default:
          Text(m.text).mta(.body1)
        }
        linkButton(m.link)
      }
      // Suggestions only under Blue's latest message.
      if isLast {
        switch m.kind {
        case "vault": SuggestionList(list: suggestions(followUp: true), send: send)
        case "notInVault", "other", "waiting": SuggestionList(list: suggestions(followUp: false), send: send)
        default: EmptyView()
        }
      }
    }
  }

  @ViewBuilder
  private func linkButton(_ link: String) -> some View {
    if link == "map" {
      BubbleLink(title: "Open map", symbol: "map.fill") { router.tab = .map; dismiss() }
    } else if link.hasPrefix("taxi:"), let item = booking(for: link) {
      BubbleLink(title: "Show taxi card", symbol: "car.fill") { taxiItem = item }
    } else if link.hasPrefix("translation:"), let entry = entry(for: link) {
      BubbleLink(title: "Show full screen", symbol: "arrow.up.left.and.arrow.down.right") { translationCard = entry }
    }
  }

  /// The booking behind a "Show taxi card" button: by its id. Older messages saved the title,
  /// so a title still works, but only when exactly one booking has it.
  private func booking(for link: String) -> VaultItem? {
    let key = String(link.dropFirst(5))
    if let item = items.first(where: { $0.uid == key }) { return item }
    let named = items.filter { $0.title == key }
    return named.count == 1 ? named[0] : nil
  }

  /// The translation behind a chat bubble: by its id, or (older messages) by its text.
  private func entry(for link: String) -> TranslationEntry? {
    guard link.hasPrefix("translation:") else { return nil }
    let key = String(link.dropFirst(12))
    return translations.first { $0.uid == key }
      ?? translations.first { $0.translation == key || $0.draftTranslation == key }
  }

  /// A translation's caption follows the catch-up pass: draft → improved, or kept for checking.
  private func liveCaption(_ m: ChatMessage) -> String? {
    if m.kind == "translation", let e = entry(for: m.link) {
      if e.checkReason != nil { return "On-device · Draft kept · checked" }
      if e.draftTranslation != nil { return "Improved in the cloud · \(SourceChip.format(e.improvedLatencyMs)) · was on-device" }
      if e.improvedAt != nil { return "Checked in the cloud · draft was already good" }
    }
    return m.caption.nilIfEmpty
  }

  private func captionColor(_ m: ChatMessage) -> Color {
    if m.kind == "cloud" { return MTA.accent }
    if m.kind == "waiting" { return MTA.obstacle }
    guard m.kind == "translation", let e = entry(for: m.link) else { return MTA.onTrack }
    if e.checkReason != nil { return MTA.urgent }
    if e.isDraft { return MTA.obstacle }
    return MTA.onTrack
  }

  /// "On-device · 4.1 s · From your booking" under Blue's bubble (like Messages' "Delivered").
  private func caption(_ meta: AIMeta, _ from: String?) -> String {
    var parts = [meta.source == .onDevice ? "On-device" : "Cloud · Gemini", SourceChip.format(meta.latencyMs)]
    if !net.isOnline { parts.append("Offline") }
    if let from { parts.append(from) }
    return parts.joined(separator: " · ")
  }

  /// Turns an answer into the message that's saved and shown.
  private func blueMessage(_ outcome: AskOutcome) -> ChatMessage {
    switch outcome {
    case let .vault(answer, item, meta):
      let m = ChatMessage(role: "blue", kind: "vault", text: answer.text)
      // "2026-12-03 15:00" → big "15:00" + "Thu, Dec 3"; anything else shown as-is.
      let parts = answer.value.split(separator: " ")
      if parts.count == 2, let d = TripTimeline.date(String(parts[0]), String(parts[1])) {
        m.value = TripTimeline.time(d); m.subtitle = TripTimeline.dayTitle(d)
      } else { m.value = answer.value }
      m.sourceTitle = item.title
      m.sourceRef = item.confirmationCode ?? ""
      m.sourceSymbol = item.kind == "hotel" ? "bed.double.fill" : item.kind == "train" ? "tram.fill" : "airplane"
      m.caption = caption(meta, "From your booking")
      if answer.showTaxiCard { m.link = "taxi:\(item.uid)" }
      return m
    case let .place(answer, place, meta):
      let m = ChatMessage(role: "blue", kind: "place", text: answer.text)
      m.value = answer.distance; m.subtitle = answer.estimate
      m.sourceTitle = place.name; m.sourceSymbol = place.symbol
      m.caption = caption(meta, "From your offline map"); m.link = "map"
      return m
    case let .notInVault(meta):
      let m = ChatMessage(role: "blue", kind: "notInVault", text: "That isn't in your saved bookings, so I won't guess.")
      m.caption = caption(meta, nil)
      return m
    case let .translation(entry, meta):
      let m = ChatMessage(role: "blue", kind: "translation", text: entry.sourceText)
      m.value = entry.translation; m.subtitle = entry.romanization; m.note = entry.note
      m.caption = caption(meta, entry.isDraft ? "Draft · Say in \(language)" : "Say in \(language)")
      m.link = "translation:\(entry.uid)"
      return m
    case let .other(meta):
      let m = ChatMessage(role: "blue", kind: "other",
                          text: "Hi! Ask me about your bookings, your saved places, or anything about the trip. Tap あ to say something in \(language).")
      m.caption = caption(meta, nil)
      return m
    case let .cloudAnswer(answer, meta):
      let m = ChatMessage(role: "blue", kind: "cloud", text: answer)
      m.caption = caption(meta, "General advice, not from your bookings")
      return m
    case .waiting:
      // The question is kept in `note`; the catch-up pass answers it when the connection is back.
      let m = ChatMessage(role: "blue", kind: "waiting",
                          text: "You're offline, so I'll answer this when you're back online. Meanwhile I can still answer from your bookings, show distances, or translate (あ).")
      m.caption = "Offline · waiting for a connection"
      return m
    }
  }

  // MARK: - Suggestions (each one is answerable from a stored field)

  private func suggestions(followUp: Bool) -> [Suggestion] {
    let kinds = Set(items.map(\.kind))
    var list: [Suggestion] = []
    if kinds.contains("hotel") {
      list += [.init(text: "When is hotel check-in?", symbol: "bed.double.fill"),
               .init(text: "Show my hotel to a taxi driver", symbol: "car.fill"),
               .init(text: "When is check-out?", symbol: "door.left.hand.open")]
    }
    if kinds.contains("train") { list.append(.init(text: "When does my train leave?", symbol: "tram.fill")) }
    if kinds.contains("flight") { list.append(.init(text: "What's my flight booking code?", symbol: "airplane")) }
    if let plan = places.first(where: { $0.kind == "plan" }) {
      list.append(.init(text: "How far is \(plan.name) from my hotel?", symbol: "map.fill"))
    }
    if list.isEmpty { list = [.init(text: "What's my booking code?", symbol: "doc.text.fill")] }
    // After an answer, offer two follow-ups you haven't asked yet.
    if followUp {
      let asked = Set(messages.filter { $0.role == "you" }.map(\.text))
      return Array(list.filter { !asked.contains($0.text) }.prefix(2))
    }
    return Array(list.prefix(4))
  }

  // MARK: - Sending

  private func send(_ text: String) {
    guard let q = text.nilIfEmpty, !asking else { return }
    question = ""
    let say = sayMode
    withAnimation(.snappy) {
      context.insert(ChatMessage(role: "you", kind: "text", text: q))
      asking = true
    }
    try? context.save()
    Task {
      let reply: ChatMessage
      do {
        let here = location.location.map { (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
        let r = say
          ? try await ai.say(q, items: items, pack: pack)
          : try await ai.ask(q, items: items, pack: pack, places: places, here: here)
        reply = blueMessage(r)
        if reply.kind == "waiting" { reply.note = q }   // the question, for the catch-up pass
      } catch {
        reply = ChatMessage(role: "blue", kind: "error", text: error.localizedDescription)
      }
      withAnimation(.snappy) { context.insert(reply); asking = false }
      try? context.save()
    }
  }

  private func clear() {
    withAnimation(.snappy) { for m in messages { context.delete(m) } }
    try? context.save()
  }
}

// MARK: - Pieces

/// Blue's logo: the brand asterisk on an accent circle.
struct BlueAvatar: View {
  var size: CGFloat = 28
  var body: some View {
    Image(systemName: "asterisk").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(MTA.onColor)
      .frame(width: size, height: size).background(MTA.accent, in: .circle)
      .accessibilityHidden(true)
  }
}

/// One of Blue's messages: logo at the bottom-left, grey bubble, optional caption underneath.
private struct BlueRow<Content: View>: View {
  var caption: String? = nil
  var captionColor: Color = MTA.onTrack
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        BlueAvatar()
        VStack(alignment: .leading, spacing: 6) { content }
          .foregroundStyle(MTA.text)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(MTA.raised, in: .rect(cornerRadius: 20))
        Spacer(minLength: 40)
      }
      if let caption {
        Text(caption.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
          .foregroundStyle(captionColor).padding(.leading, 36)
      }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}

/// "From your booking" inset inside Blue's bubble.
private struct BookingSource: View {
  let title: String
  let ref: String?
  let symbol: String
  var body: some View {
    HStack(spacing: 10) {
      TripBullet(systemName: symbol, size: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).mta(.body2).fontWeight(.semibold).foregroundStyle(MTA.text)
        if let ref { Text("Ref \(ref)").mta(.body2).foregroundStyle(MTA.text2) }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTA.surface, in: .rect(cornerRadius: 12))
  }
}

private struct BubbleLink: View {
  let title: String
  let symbol: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).mta(.body2).fontWeight(.semibold).foregroundStyle(MTA.accent)
    }
    .buttonStyle(.plain)
  }
}

private struct Suggestion: Hashable { let text: String; let symbol: String }

/// Tappable starter questions under Blue's message, outlined in accent.
private struct SuggestionList: View {
  let list: [Suggestion]
  var send: (String) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(list, id: \.self) { s in
        Button { send(s.text) } label: {
          HStack(spacing: 8) {
            Image(systemName: s.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 20)
            Text(s.text).mta(.button2).multilineTextAlignment(.leading)
          }
          .foregroundStyle(MTA.accent)
          .padding(.horizontal, 14).padding(.vertical, 9)
          .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.accent, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.leading, 36)
  }
}

/// Blue is working: the avatar and a typing bubble, with an optional caption under it.
/// Used wherever the app waits on AI (the plan chat, a day's stops), instead of a spinner.
struct BlueTyping: View {
  var caption: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        BlueAvatar()
        TypingDots().padding(.horizontal, 14).padding(.vertical, 10).background(MTA.raised, in: .rect(cornerRadius: 20))
      }
      if let caption { Text(caption).mta(.body2).foregroundStyle(MTA.text2).padding(.leading, 36) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(caption ?? "Blue is working on it")
  }
}

/// Blue is "typing": three dots that pulse in turn.
struct TypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { tl in
      let t = tl.date.timeIntervalSinceReferenceDate
      HStack(spacing: 5) {
        ForEach(0..<3) { i in
          Circle().fill(MTA.text2).frame(width: 8, height: 8)
            .opacity(reduceMotion ? 0.6 : 0.3 + 0.7 * max(0, sin((t * 4) - Double(i) * 0.7)))
        }
      }
      .padding(.vertical, 6)
    }
    .accessibilityLabel("Blue is answering")
  }
}

/// Text in a photo (a sign, a menu), read on this iPhone with Vision. Nothing is uploaded.
enum TextInImage {
  static func read(_ image: CGImage) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "ko-KR", "zh-Hans", "en-US", "fr-FR", "es-ES", "de-DE", "it-IT", "pt-BR"]
    request.usesLanguageCorrection = true
    try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
  }
}
