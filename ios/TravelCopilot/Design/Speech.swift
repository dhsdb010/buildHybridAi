import AVFoundation
import SwiftUI
import UIKit

/// Reads local-language text aloud with the built-in iOS voice. Works offline (no network, no AI).
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = Speaker()
  private let synth = AVSpeechSynthesizer()
  private(set) var speakingID: String?

  override init() {
    super.init()
    synth.delegate = self
  }

  static func voice(for languageCode: String?) -> AVSpeechSynthesisVoice? {
    let code = String((languageCode ?? "").prefix(2))
    return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) && $0.quality == .enhanced }
      ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) }
  }

  func toggle(_ text: String, languageCode: String?, id: String, slow: Bool = false) {
    if speakingID == id { synth.stopSpeaking(at: .immediate); speakingID = nil; return }
    synth.stopSpeaking(at: .immediate)
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
    let u = AVSpeechUtterance(string: text)
    u.voice = Self.voice(for: languageCode)
    u.rate = slow ? 0.38 : 0.47
    speakingID = id
    synth.speak(u)
  }

  func stop() { synth.stopSpeaking(at: .immediate); speakingID = nil }

  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
    Task { @MainActor in self.speakingID = nil }
  }
  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
    Task { @MainActor in self.speakingID = nil }
  }
}

/// Round "play" button (speaker.wave.2.fill ↔ stop.fill).
struct SpeakButton: View {
  let text: String
  let languageCode: String?
  let id: String
  var label: String = "Play"
  var slow = false
  @State private var speaker = Speaker.shared

  var body: some View {
    let playing = speaker.speakingID == id
    Button { speaker.toggle(text, languageCode: languageCode, id: id, slow: slow) } label: {
      HStack(spacing: 8) {
        Image(systemName: playing ? "stop.fill" : "speaker.wave.2.fill")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 44, height: 44)
          .background(MTA.accent, in: .circle)
          .foregroundStyle(MTA.onColor)
        Text(playing ? "Stop" : label).mta(.button2).foregroundStyle(.white)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(playing ? "Stop" : label)
  }
}

// MARK: - Keyboards

enum Keyboards {
  /// True if the user has a keyboard for this language (e.g. Japanese) installed.
  @MainActor static func has(_ languageCode: String?) -> Bool {
    guard let code = languageCode?.prefix(2), !code.isEmpty else { return true }
    if code == "en" { return true }
    return UITextInputMode.activeInputModes.contains { ($0.primaryLanguage ?? "").hasPrefix(String(code)) }
  }

  static func name(for languageCode: String?) -> String {
    Locale(identifier: "en").localizedString(forLanguageCode: String((languageCode ?? "").prefix(2))) ?? "local"
  }
}

/// Text field that opens directly on the local-language keyboard when it is installed.
struct LocalTextField: UIViewRepresentable {
  @Binding var text: String
  let languageCode: String?
  var placeholder: String = ""
  var onSubmit: () -> Void = {}

  final class Field: UITextField {
    var preferred: String?
    override var textInputMode: UITextInputMode? {
      if let p = preferred,
         let mode = UITextInputMode.activeInputModes.first(where: { ($0.primaryLanguage ?? "").hasPrefix(p) }) {
        return mode
      }
      return super.textInputMode
    }
  }

  func makeUIView(context: Context) -> Field {
    let f = Field()
    f.preferred = languageCode.map { String($0.prefix(2)) }
    f.font = .systemFont(ofSize: 26, weight: .semibold)
    f.textColor = .white
    f.tintColor = UIColor(MTA.notice)
    f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)])
    f.returnKeyType = .done
    // Never let long text widen the layout.
    f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    f.setContentHuggingPriority(.defaultLow, for: .horizontal)
    f.adjustsFontSizeToFitWidth = true
    f.minimumFontSize = 16
    f.delegate = context.coordinator
    f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
    DispatchQueue.main.async { f.becomeFirstResponder() }
    return f
  }

  func updateUIView(_ f: Field, context: Context) { if f.text != text { f.text = text } }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: LocalTextField
    init(_ p: LocalTextField) { parent = p }
    @objc func changed(_ f: UITextField) { parent.text = f.text ?? "" }
    func textFieldShouldReturn(_ f: UITextField) -> Bool { parent.onSubmit(); return true }
  }
}
