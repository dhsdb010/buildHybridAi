import AuthenticationServices
import SwiftUI

/// First launch, before Welcome: sign in with Google or Apple, or skip.
/// Offline features never need an account; planning with Gemini does.
struct SignInView: View {
  /// Called after a successful sign-in or "Continue without an account".
  var onDone: () -> Void
  /// Shown as a gate before planning: no skip button, different headline.
  var required = false

  @Environment(AuthService.self) private var auth
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      BrandBadge(color: MTA.accent, size: 120).padding(.top, 8)
      Text(required ? "Sign in to plan with AI" : "Sign in to plan your trip")
        .mta(.displayLarge).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
      Text("Your account unlocks planning with Gemini and keeps a backup of your trip. What you need on the road still works offline.")
        .mta(.body1).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 12) {
        perk("icloud", "Plan with Gemini and Google Maps")
        perk("square.and.arrow.down", "Your trip backed up to your account")
        perk("iphone", "Ask, translate and the taxi card work offline, no account needed")
      }
      .padding(.top, 4)
      Spacer(minLength: 0)
      if let e = auth.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent).fixedSize(horizontal: false, vertical: true) }

      Button { Task { await auth.signInWithGoogle() } } label: {
        HStack(spacing: 12) {
          GoogleG().frame(width: 20, height: 20)
          Text("Continue with Google").mta(.button1).foregroundStyle(MTA.text)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(MTA.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 1.5) }
      }
      .buttonStyle(.plain)

      SignInWithAppleButton(.signIn) { auth.prepare($0) } onCompletion: { r in Task { await auth.complete(r) } }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 52).clipShape(.capsule)

      if !required {
        Button("Continue without an account") { onDone() }
          .mta(.button2).foregroundStyle(MTA.accent).frame(maxWidth: .infinity)
      }
      Text("We only get your name and email. Bookings stay on this iPhone.")
        .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
    .mtaScreen().padding(.top, 12).padding(.bottom, 12)
    .background(MTA.surface)
    .disabled(auth.busy)
    .overlay { if auth.busy { ProgressView() } }
    .onChange(of: auth.isSignedIn) { _, signedIn in if signedIn { onDone() } }
  }

  private func perk(_ symbol: String, _ text: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(MTA.accent).frame(width: 24)
      Text(text).mta(.body2).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Google "G" logo (brand colors, as Google's sign-in button guidelines require).
struct GoogleG: View {
  var body: some View {
    Canvas { ctx, size in
      let s = size.width / 48
      func path(_ d: (inout Path) -> Void) -> Path { var p = Path(); d(&p); return p.applying(.init(scaleX: s, y: s)) }
      let red = path { p in
        p.move(to: .init(x: 24, y: 9.5)); p.addCurve(to: .init(x: 33.21, y: 13.1), control1: .init(x: 27.54, y: 9.5), control2: .init(x: 30.71, y: 10.72))
        p.addLine(to: .init(x: 40.06, y: 6.25)); p.addCurve(to: .init(x: 24, y: 0), control1: .init(x: 35.9, y: 2.38), control2: .init(x: 30.47, y: 0))
        p.addCurve(to: .init(x: 2.56, y: 13.22), control1: .init(x: 14.62, y: 0), control2: .init(x: 6.51, y: 5.38))
        p.addLine(to: .init(x: 10.54, y: 19.41)); p.addCurve(to: .init(x: 24, y: 9.5), control1: .init(x: 12.43, y: 13.72), control2: .init(x: 17.74, y: 9.5))
        p.closeSubpath()
      }
      let blue = path { p in
        p.move(to: .init(x: 46.98, y: 24.55)); p.addCurve(to: .init(x: 46.6, y: 20), control1: .init(x: 46.98, y: 22.98), control2: .init(x: 46.83, y: 21.46))
        p.addLine(to: .init(x: 24, y: 20)); p.addLine(to: .init(x: 24, y: 29.02)); p.addLine(to: .init(x: 36.94, y: 29.02))
        p.addCurve(to: .init(x: 32.16, y: 36.2), control1: .init(x: 36.36, y: 31.98), control2: .init(x: 34.68, y: 34.5))
        p.addLine(to: .init(x: 39.89, y: 42.2)); p.addCurve(to: .init(x: 46.98, y: 24.55), control1: .init(x: 44.4, y: 38.02), control2: .init(x: 46.98, y: 31.84))
        p.closeSubpath()
      }
      let yellow = path { p in
        p.move(to: .init(x: 10.53, y: 28.59)); p.addCurve(to: .init(x: 9.77, y: 24), control1: .init(x: 10.05, y: 27.14), control2: .init(x: 9.77, y: 25.6))
        p.addCurve(to: .init(x: 10.53, y: 19.41), control1: .init(x: 9.77, y: 22.4), control2: .init(x: 10.04, y: 20.86))
        p.addLine(to: .init(x: 2.55, y: 13.22)); p.addCurve(to: .init(x: 0, y: 24), control1: .init(x: 0.92, y: 16.46), control2: .init(x: 0, y: 20.12))
        p.addCurve(to: .init(x: 2.56, y: 34.78), control1: .init(x: 0, y: 27.88), control2: .init(x: 0.92, y: 31.54))
        p.closeSubpath()
      }
      let green = path { p in
        p.move(to: .init(x: 24, y: 48)); p.addCurve(to: .init(x: 39.89, y: 42.19), control1: .init(x: 30.48, y: 48), control2: .init(x: 35.93, y: 45.87))
        p.addLine(to: .init(x: 32.16, y: 36.19)); p.addCurve(to: .init(x: 24, y: 38.49), control1: .init(x: 30.01, y: 37.64), control2: .init(x: 27.24, y: 38.49))
        p.addCurve(to: .init(x: 10.53, y: 28.58), control1: .init(x: 17.74, y: 38.49), control2: .init(x: 12.43, y: 34.27))
        p.addLine(to: .init(x: 2.55, y: 34.77)); p.addCurve(to: .init(x: 24, y: 48), control1: .init(x: 6.51, y: 42.62), control2: .init(x: 14.62, y: 48))
        p.closeSubpath()
      }
      ctx.fill(red, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))
      ctx.fill(blue, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
      ctx.fill(yellow, with: .color(Color(red: 0.984, green: 0.737, blue: 0.020)))
      ctx.fill(green, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))
    }
    .accessibilityHidden(true)
  }
}
