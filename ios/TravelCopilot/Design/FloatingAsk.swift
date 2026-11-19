import SwiftUI

/// The Blue button: the brand mark with "NEED HELP? · ASK ANYTHING!" turning around it.
/// It stays at the side of the screen and only opens Blue's chat page when tapped.
struct FloatingAsk: View {
  @Environment(AppRouter.self) private var router
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack {
      Spacer(minLength: 0)
      Button { router.ask = AskRequest() } label: {
        ZStack {
          Circle().fill(MTA.surface.opacity(0.94))
            .shadow(color: .black.opacity(0.14), radius: 7, y: 4)
          // Angle comes from the clock, so only the rotation changes. (A repeatForever
          // animation also caught the badge's first layout and sent the ring drifting.)
          TimelineView(.animation(paused: reduceMotion)) { tl in
            RingText(text: "NEED HELP? · ASK ANYTHING! · ", radius: 34.5)
              .foregroundStyle(MTA.accent)
              .rotationEffect(.degrees(reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 16) / 16 * 360))
          }
          .frame(width: 84, height: 84)
          BlueAvatar(size: 48)
        }
        .frame(width: 84, height: 84)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Ask Blue")
      .accessibilityHint("Opens the chat with Blue, your trip assistant")
    }
    .padding(.horizontal, MTA.margin)
    .padding(.bottom, 8)
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
