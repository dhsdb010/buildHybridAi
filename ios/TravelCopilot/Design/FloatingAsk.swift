import SwiftUI

/// The brand button as a floating AI button, with "NEED HELP? · ASK ANYTHING!" running around it.
/// Tap it and it opens into a chat bar (just the field, close and send — no logo);
/// sending opens Ask with the question (on-device first, offline-safe).
struct FloatingAsk: View {
  var placeholder = "Need help? Ask anything"
  @Environment(AppRouter.self) private var router
  @State private var open = false
  @State private var spin = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var text = ""
  @FocusState private var focused: Bool
  @Namespace private var ns

  var body: some View {
    HStack {
      Spacer(minLength: 0)
      if open { bar } else { badge }
    }
    .padding(.horizontal, MTA.margin)
    .padding(.bottom, 8)
    .animation(.snappy(duration: 0.3), value: open)
    #if DEBUG
    .onAppear {
      // `-askBar open` (add `-askText "…"` to see the send state).
      if UserDefaults.standard.string(forKey: "askBar") == "open" { open = true; text = UserDefaults.standard.string(forKey: "askText") ?? "" }
    }
    #endif
  }

  private var badge: some View {
    Button {
      open = true
      Task { try? await Task.sleep(for: .milliseconds(250)); focused = true }
    } label: {
      ZStack {
        Circle().fill(MTA.surface.opacity(0.94))
          .shadow(color: .black.opacity(0.14), radius: 7, y: 4)
        // The letters slowly circle the button (still when Reduce Motion is on).
        RingText(text: "NEED HELP? · ASK ANYTHING! · ", radius: 34.5)
          .foregroundStyle(MTA.accent)
          .rotationEffect(.degrees(spin ? 360 : 0))
          .animation(reduceMotion ? nil : .linear(duration: 16).repeatForever(autoreverses: false), value: spin)
          .onAppear { if !reduceMotion { spin = true } }
        Image(systemName: "asterisk").font(.system(size: 22, weight: .bold)).foregroundStyle(MTA.onColor)
          .frame(width: 48, height: 48)
          .background(MTA.accent, in: .circle)
          .matchedGeometryEffect(id: "ask", in: ns)
      }
      .frame(width: 84, height: 84)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Ask Travel Copilot")
    .accessibilityHint("Opens the chat bar")
  }

  private var bar: some View {
    // As plain as Safari's search bar: one field, one round button beside it.
    // The button is ✕ while the field is empty and becomes ↑ send once you type;
    // the keyboard's return key sends too.
    HStack(alignment: .bottom, spacing: 10) {
      field
      actionButton
    }
  }

  private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  private var field: some View {
    // Grows with the question up to 5 lines, then scrolls inside (like Messages).
    TextField(placeholder, text: $text, axis: .vertical)
      .lineLimit(1...5)
      .mta(.body1).foregroundStyle(MTA.text)
      .focused($focused).submitLabel(.send)
      .onChange(of: text) { _, new in
        // A multi-line field puts return into the text; return still means send.
        if new.hasSuffix("\n") { text = String(new.dropLast()); send() }
      }
      .padding(.horizontal, 20).padding(.vertical, 14)
      .frame(minHeight: 52)
      // Solid backing so long text stays readable over cards (Safari's bar is near-opaque too).
      .background(MTA.surface.opacity(0.94), in: .rect(cornerRadius: 26))
      .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
      .matchedGeometryEffect(id: "ask", in: ns)
  }

  private var actionButton: some View {
    let empty = isEmpty
    return Button {
      if empty { close() } else { send() }
    } label: {
      Image(systemName: empty ? "xmark" : "arrow.up")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(empty ? MTA.text : MTA.onColor)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 52, height: 52)
        .background(Circle().fill(empty ? Color.clear : MTA.accent))
        .glassEffect(.regular.interactive(), in: .circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(empty ? "Close chat" : "Send")
    .animation(.snappy(duration: 0.2), value: empty)
  }

  private func send() {
    let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
    router.ask = AskRequest(mode: 0, text: q, autoSubmit: !q.isEmpty)
    text = ""; focused = false; open = false
  }

  private func close() {
    focused = false; open = false
  }
}

/// Text set around a circle, reading clockwise from the top (like the brand badge ring).
struct RingText: View {
  let text: String
  let radius: CGFloat
  var size: CGFloat = 8

  var body: some View {
    let chars = Array(text)
    // Spread evenly round the full circle; narrow glyphs get a bit less room.
    let weights = chars.map { c -> CGFloat in c == " " ? 0.55 : ".·!?".contains(c) ? 0.6 : (c == "W" || c == "M" ? 1.3 : 1) }
    let total = weights.reduce(0, +)
    let starts = weights.indices.map { i in weights[..<i].reduce(0, +) + weights[i] / 2 }
    ZStack {
      ForEach(chars.indices, id: \.self) { i in
        Text(String(chars[i]))
          .font(.custom("HelveticaNeue-Bold", size: size))
          .offset(y: -radius)
          .rotationEffect(.degrees(Double(starts[i] / total) * 360))
      }
    }
    .accessibilityHidden(true)
  }
}
