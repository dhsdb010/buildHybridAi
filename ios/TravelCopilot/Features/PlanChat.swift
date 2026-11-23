import AVFoundation
import FoundationModels
import PDFKit
import PhotosUI
import Speech
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Composer

/// The plan chat's bar: "Blue is AI and can make mistakes." above it; + on the left; the text
/// field; then mic + Talk while it's empty, or Send once there's text.
struct PlanComposer: View {
  @Binding var text: String
  var placeholder: String
  var focused: FocusState<Bool>.Binding
  var canSend: Bool
  @Bindable var speech: SpeechInput
  var onSend: () -> Void
  var onPlus: () -> Void
  var onTalk: () -> Void
  /// Something to the left of the bar (Blue's chat puts its あ button here).
  var leading: AnyView? = nil

  private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    VStack(spacing: 8) {
      Text("Blue is AI and can make mistakes.").mta(.body2).foregroundStyle(MTA.text2)
      HStack(spacing: 8) {
      if let leading { leading }
      HStack(spacing: 6) {
        Button(action: onPlus) {
          Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(MTA.text)
            .frame(width: 36, height: 40)
        }
        .accessibilityLabel("Add photos or files")
        TextField(speech.listening ? "Listening…" : placeholder, text: $text, axis: .vertical)
          .mta(.body1).lineLimit(1...3).focused(focused).submitLabel(.send).onSubmit(onSend)
        if empty {
          Button { speech.toggleDictation { text = $0 } } label: {
            Image(systemName: speech.listening ? "mic.fill" : "mic")
              .font(.system(size: 19, weight: .medium))
              .foregroundStyle(speech.listening ? MTA.accent : MTA.text2)
              .frame(width: 36, height: 40)
          }
          .accessibilityLabel(speech.listening ? "Stop dictation" : "Dictate")
          Button(action: onTalk) {
            HStack(spacing: 6) {
              Image(systemName: "waveform.low").font(.system(size: 15, weight: .semibold))
              Text("Talk").mta(.button2)
            }
            .foregroundStyle(MTA.onColor)
            .padding(.horizontal, 14).frame(height: 38)
            .background(MTA.accent, in: .capsule)
          }
          .accessibilityLabel("Talk with Blue")
        } else {
          Button(action: onSend) {
            Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.onColor)
              .frame(width: 38, height: 38).background(MTA.accent, in: .circle)
          }
          .disabled(!canSend)
          .accessibilityLabel("Send")
        }
      }
      .padding(.leading, 6).padding(.trailing, 5).padding(.vertical, 5)
      .background(MTA.surface, in: .rect(cornerRadius: 26))
      .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(MTA.border, lineWidth: 2) }
      }
      if let e = speech.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
    }
  }
}

// MARK: - Speech (on this iPhone)

/// Speech to text with Apple's recognizer, on the device when it can. Dictation fills the text
/// field; Talk mode hands each finished sentence (after a short pause) to Blue.
@MainActor
@Observable
final class SpeechInput {
  private(set) var listening = false
  var error: String?
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var pause: Task<Void, Never>?

  func toggleDictation(onText: @escaping (String) -> Void) {
    if listening { stop() } else { Task { await start(finishAfterPause: false, onText: onText, onDone: { _ in }) } }
  }

  /// Listens until the speaker pauses, then calls `onDone` with what was said.
  func listenOnce(onText: @escaping (String) -> Void, onDone: @escaping (String) -> Void) async {
    await start(finishAfterPause: true, onText: onText, onDone: onDone)
  }

  private func start(finishAfterPause: Bool, onText: @escaping (String) -> Void, onDone: @escaping (String) -> Void) async {
    error = nil
    guard await Self.authorized() else {
      error = "Turn on Microphone and Speech Recognition for Travel Copilot in Settings to talk to Blue."
      return
    }
    guard let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
    stop()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let req = SFSpeechAudioBufferRecognitionRequest()
      req.shouldReportPartialResults = true
      req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
      request = req
      let input = engine.inputNode
      input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buffer, _ in
        req?.append(buffer)
      }
      engine.prepare()
      try engine.start()
      listening = true
      var latest = ""
      task = recognizer.recognitionTask(with: req) { [weak self] result, err in
        let text = result?.bestTranscription.formattedString
        let final = result?.isFinal ?? false
        Task { @MainActor in
          guard let self else { return }
          if let text { latest = text; onText(text) }
          if finishAfterPause, text != nil {
            self.pause?.cancel()
            self.pause = Task { @MainActor in
              try? await Task.sleep(for: .seconds(1.4))
              guard !Task.isCancelled, self.listening else { return }
              self.stop(); onDone(latest)
            }
          }
          if final || err != nil {
            if self.listening { self.stop(); if finishAfterPause { onDone(latest) } }
          }
        }
      }
    } catch {
      self.error = "Couldn't start the microphone: \(error.localizedDescription)"
      stop()
    }
  }

  func stop() {
    pause?.cancel(); pause = nil
    if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
    request?.endAudio(); request = nil
    task?.cancel(); task = nil
    listening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private static func authorized() async -> Bool {
    let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    guard speech == .authorized else { return false }
    return await AVAudioApplication.requestRecordPermission()
  }
}

// MARK: - Talk mode

/// Hands-free: you speak, Blue answers out loud, and it listens again until you stop.
struct TalkSheet: View {
  enum Phase { case listening, thinking, speaking }
  @Binding var phase: Phase
  var heard: String
  var reply: String
  var onStop: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 22) {
      Spacer(minLength: 12)
      TimelineView(.animation(paused: reduceMotion || phase == .thinking)) { tl in
        let t = tl.date.timeIntervalSinceReferenceDate
        BlueAvatar(size: 96)
          .scaleEffect(phase == .thinking || reduceMotion ? 1 : 1 + 0.06 * sin(t * (phase == .speaking ? 7 : 3)))
          .background { Circle().fill(MTA.accent.opacity(0.15)).frame(width: 150, height: 150) }
      }
      Text(phase == .listening ? "Listening…" : phase == .thinking ? "Blue is thinking…" : "Blue is speaking…")
        .mta(.headline).foregroundStyle(MTA.text)
      if !heard.isEmpty { Text("“\(heard)”").mta(.body1).foregroundStyle(MTA.text2).multilineTextAlignment(.center) }
      if !reply.isEmpty && phase == .speaking {
        Text(reply).mta(.body1).foregroundStyle(MTA.text).multilineTextAlignment(.center)
      }
      Spacer()
      Text("Blue is AI and can make mistakes.").mta(.body2).foregroundStyle(MTA.text2)
      Button("Stop talking", action: onStop).buttonStyle(.mtaPrimary)
    }
    .mtaScreen().padding(.bottom, 16)
    .background(MTA.surface)
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled()
  }
}

// MARK: - Add to chat

/// "+" sheet: recent photos in a row, the full library, Camera, and Add files.
struct AddToChatSheet: View {
  @Binding var photos: [PhotosPickerItem]
  var onCamera: () -> Void
  var onFiles: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Color.clear.frame(height: 6)
      HStack {
        Button { onClose() } label: {
          Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.text)
            .frame(width: 40, height: 40).background(MTA.raised, in: .circle)
        }
        .accessibilityLabel("Close")
        Spacer()
        Text("Add to chat").mta(.subheadNormal).foregroundStyle(MTA.text)
        Spacer()
        PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) {
          Text("Photos").font(.system(size: 16, weight: .medium)).foregroundStyle(Color(red: 0, green: 0.31, blue: 0.92))
        }
      }
      PhotosPicker(selection: $photos, maxSelectionCount: 6, selectionBehavior: .continuous, matching: .images) { EmptyView() }
        .photosPickerStyle(.compact)
        .photosPickerDisabledCapabilities([.search, .collectionNavigation, .stagingArea])
        .photosPickerAccessoryVisibility(.hidden)
        .frame(height: 112)
      VStack(spacing: 0) {
        row("camera", "Camera", enabled: UIImagePickerController.isSourceTypeAvailable(.camera)) { onCamera() }
        Rectangle().fill(MTA.subtle).frame(height: 1).padding(.leading, 52)
        row("arrow.up.document", "Add files", enabled: true) { onFiles() }
      }
      .background(MTA.raised, in: .rect(cornerRadius: 16))
      Text("Add files: PDFs, documents, booking emails. Read on this iPhone first; only what Blue needs goes to the cloud.")
        .mta(.body2).foregroundStyle(MTA.text2)
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
    .background(MTA.surface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    .overlay(alignment: .top) { Capsule().fill(MTA.subtle).frame(width: 40, height: 5).padding(.top, 6) }
    .onChange(of: photos) { if !photos.isEmpty { onClose() } }
  }

  private func row(_ symbol: String, _ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol).font(.system(size: 20)).frame(width: 24)
        Text(title).mta(.body1)
        Spacer()
        if !enabled { Text("No camera").mta(.body2).foregroundStyle(MTA.text2) }
      }
      .foregroundStyle(enabled ? MTA.text : MTA.text2)
      .padding(.horizontal, 16).frame(height: 54).contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

/// System camera, returning one photo.
struct CameraPicker: UIViewControllerRepresentable {
  var onImage: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let c = UIImagePickerController()
    c.sourceType = .camera
    c.delegate = context.coordinator
    return c
  }
  func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker
    init(_ p: CameraPicker) { parent = p }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
      parent.dismiss()
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
  }
}

// MARK: - Attachments in the chat

struct PlanAttachment: Identifiable {
  let id = UUID()
  let step: PlanSession.Step
  var fileName: String?
  var pages: Int?
  var thumbs: [UIImage] = []
  var note = ""
  /// Blue's reply, once it has read the attachment.
  var reply: String?
  /// Text of a booking confirmation, offered for the Vault.
  var bookingText: String?
  var added = false
}

struct AttachmentTurn: View {
  let a: PlanAttachment
  var onAddBookings: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ChatYou(a.note) {
        if !a.thumbs.isEmpty {
          HStack(spacing: 6) {
            ForEach(Array(a.thumbs.prefix(4).enumerated()), id: \.offset) { _, img in
              Image(uiImage: img).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 10))
            }
          }
          .accessibilityLabel("\(a.thumbs.count) photo\(a.thumbs.count == 1 ? "" : "s")")
        }
        if let name = a.fileName {
          HStack(spacing: 10) {
            Image(systemName: "doc.text.fill").font(.system(size: 22)).foregroundStyle(MTA.onColor)
            VStack(alignment: .leading, spacing: 1) {
              Text(name).mta(.button2).foregroundStyle(MTA.onColor).lineLimit(1)
              if let pages = a.pages { Text("\(pages) page\(pages == 1 ? "" : "s")").mta(.label).foregroundStyle(MTA.onColor.opacity(0.85)) }
            }
          }
          .padding(8).background(.white.opacity(0.18), in: .rect(cornerRadius: 12))
        }
      }
      if let reply = a.reply {
        ChatAI(reply)
        if a.bookingText != nil && !a.added {
          FlowLayout { QuickChip(text: "Add to my bookings", selected: true, action: onAddBookings) }.padding(.leading, 36)
        }
      } else {
        BlueTyping(caption: a.fileName == nil ? "Reading your photos on this iPhone" : "Reading it on this iPhone")
      }
    }
  }
}

@Generable
struct FileGist: Sendable {
  @Guide(description: "What this document says about the traveler's taste or plans, in at most 25 words, starting with a lowercase word, e.g. 'dawn fish markets, tile workshops, slow tram rides'")
  var gist: String
}

enum FileReader {
  /// Plain text from a picked file, read on this iPhone. Returns the text and page count (PDFs).
  static func read(_ url: URL) -> (text: String, pages: Int?)? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let type = UTType(filenameExtension: url.pathExtension)
    if type?.conforms(to: .pdf) == true, let pdf = PDFDocument(url: url) {
      return (pdf.string ?? "", pdf.pageCount)
    }
    if type?.conforms(to: .rtf) == true,
       let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return (a.string, nil) }
    if let s = try? String(contentsOf: url, encoding: .utf8) { return (s, nil) }
    return nil
  }

  /// Booking confirmations go to the Vault (Prepare), not into the plan's taste.
  static func looksLikeBooking(_ text: String) -> Bool {
    let words = ["confirmation", "reservation", "booking reference", "booking ref", "e-ticket", "check-in", "itinerary", "confirmation number"]
    let lower = text.lowercased()
    return words.filter { lower.contains($0) }.count >= 2
  }

  static let types: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, .html, .image,
                                UTType("com.apple.mail.email") ?? .data, UTType(filenameExtension: "eml") ?? .data]
}
