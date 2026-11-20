import SwiftUI
import SwiftData

/// First launch: what the app does, then set up the trip once on Wi-Fi (bookings → pack → places → offline map).
struct WelcomeView: View {
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Environment(AuthService.self) private var auth
  @Environment(\.dismiss) private var dismiss
  @AppStorage("onboarded") private var onboarded = false
  @AppStorage("signInSeen") private var signInSeen = false
  @State private var page = 0          // 0 welcome · 3 booked yet? · 1 bookings · 2 building
  @State private var showPlan = false
  @State private var signInGate = false
  @State private var text = ""
  @State private var current: PrepareService.Step?
  @State private var done: Set<PrepareService.Step> = []
  @State private var summary: PrepareService.Summary?
  @State private var error: String?
  @FocusState private var editorFocused: Bool
  @Query private var emergencyCards: [EmergencyCard]
  @State private var settingUpCard = false

  var body: some View {
    Group {
      if !signInSeen {
        SignInView { signInSeen = true }
      } else {
        switch page {
        case 0: welcome
        case 3: bookedYet
        case 1: bookings
        case 4: emergencyIntro
        default: building
        }
      }
    }
    .animation(.snappy, value: page)
    .animation(.snappy, value: signInSeen)
    .fullScreenCover(isPresented: $showPlan) {
      PlanView(onBooked: { showPlan = false; page = 1 }, onClose: { showPlan = false })
    }
    .sheet(isPresented: $signInGate) {
      SignInView(onDone: { signInGate = false; showPlan = true }, required: true)
    }
    .task {
      #if DEBUG
        if let p = UserDefaults.standard.string(forKey: "welcomePage"), let n = Int(p) { page = n }
        // `-planAuto`: open the plan chat straight away (see PlanView.debugAuto).
        if ProcessInfo.processInfo.arguments.contains("-planAuto") { signInSeen = true; page = 3; showPlan = true }
        // `-welcomeAuto`: fill the sample trip and build, to check the whole set-up end to end.
        if ProcessInfo.processInfo.arguments.contains("-welcomeAuto") {
          try? await Task.sleep(for: .seconds(2))
          text = PrepareService.sampleEmail
          Task { await build() }
        }
      #endif
    }
  }

  // MARK: - 1 · Welcome (MTA lifestyle poster)

  private var welcome: some View {
    ZStack {
      MTA.accent.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 22) {
        BrandBadge(color: MTA.onColor)
        Text("Your trip, even with no signal.").mta(.displayLarge).foregroundStyle(MTA.onColor)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 16) {
          stage(1, "Prepare · on Wi-Fi", "Bookings, phrases and a map — saved once.")
          stage(2, "Survive · offline", "Ask, translate and find your hotel with no data.")
          stage(3, "Catch up · back on Wi-Fi", "Offline drafts get polished in the cloud.")
        }
        .padding(.top, 6)
        Spacer(minLength: 0)
        Button { page = 3 } label: {
          Text("Set up my trip").mta(.button1).foregroundStyle(MTA.accent)
            .frame(maxWidth: .infinity, minHeight: 52).background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
        Button("I'll do it later") { finish() }
          .mta(.button2).foregroundStyle(MTA.onColor).frame(maxWidth: .infinity)
      }
      .mtaScreen().padding(.top, 24).padding(.bottom, 12)
    }
    .environment(\.colorScheme, .dark)
  }

  private func stage(_ n: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(n)").mta(.button2).foregroundStyle(MTA.accent).frame(width: 36, height: 36).background(.white, in: .circle)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).mta(.subheadNormal).foregroundStyle(MTA.onColor)
        Text(detail).mta(.body2).foregroundStyle(MTA.onColor.opacity(0.8))
      }
    }
  }

  // MARK: - Booked yet? (plan with AI, or paste bookings)

  private var bookedYet: some View {
    ZStack {
      MTA.accent.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 18) {
        BrandBadge(color: MTA.onColor, size: 110)
        Text("Have you booked your trip yet?").mta(.displayLarge).foregroundStyle(MTA.onColor)
          .fixedSize(horizontal: false, vertical: true)
        Text("If not, plan it here: where to go, where to stay, what to eat. The AI checks live places and local reviews.")
          .mta(.body1).foregroundStyle(MTA.onColor).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Button { helpMePlan() } label: {
          Text("Help me plan it").mta(.button1).foregroundStyle(MTA.accent)
            .frame(maxWidth: .infinity, minHeight: 52).background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
        Button { page = 1 } label: {
          Text("Yes, add my bookings").mta(.button1).foregroundStyle(MTA.onColor)
            .frame(maxWidth: .infinity, minHeight: 52).overlay { Capsule().strokeBorder(.white, lineWidth: 2) }
        }
        .buttonStyle(.plain)
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "icloud").foregroundStyle(MTA.onColor)
          Text("Planning needs internet. Your trip works offline later.").mta(.body2).foregroundStyle(MTA.onColor)
        }
        .frame(maxWidth: .infinity)
      }
      .mtaScreen().padding(.top, 24).padding(.bottom, 12)
    }
    .environment(\.colorScheme, .dark)
  }

  private func helpMePlan() {
    // Cloud planning has per-user limits, so it needs an account (offline features don't).
    if auth.isSignedIn || !TravelCopilotApp.firebaseConfigured { showPlan = true } else { signInGate = true }
  }

  // MARK: - 2 · Add bookings

  private var bookings: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          MTALabel("Step 1 of 2 · on Wi-Fi")
          Text("Add your bookings").mta(.displayMedium).foregroundStyle(MTA.text)
          Text("Paste your flight, hotel or train confirmation emails. They're read once in the cloud, then kept only on this iPhone.")
            .mta(.body1).foregroundStyle(MTA.text2)
          TextEditor(text: $text)
            .focused($editorFocused).mta(.body2).scrollContentBackground(.hidden)
            .frame(height: 170).padding(10)
            .overlay(alignment: .topLeading) {
              if text.isEmpty {
                Text("Paste confirmations here…").mta(.body2).foregroundStyle(MTA.text2).padding(.top, 18).padding(.leading, 15).allowsHitTesting(false)
              }
            }
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }
          Button("Use a sample trip to Tokyo") { text = PrepareService.sampleEmail }.buttonStyle(.mtaSecondary(height: 44))
          MTALabel("This iPhone")
          HStack(spacing: 14) {
            MilestoneSymbol(systemName: ai.deviceModelAvailable ? "checkmark" : "iphone", ok: ai.deviceModelAvailable)
            VStack(alignment: .leading, spacing: 2) {
              Text("On-device model").mta(.body1).foregroundStyle(MTA.text)
              Text(ai.deviceModelAvailable ? "Ask and Say will work offline." : "Turn on Apple Intelligence for offline answers.")
                .mta(.body2).foregroundStyle(MTA.text2)
            }
          }
          if !net.isOnline { NoticeCard(text: "You're offline. Set-up needs internet once — connect to Wi-Fi.") }
          Button("Build my offline pack") { Task { await build() } }
            .buttonStyle(.mtaPrimary).disabled(text.nilIfEmpty == nil || !net.isOnline)
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.immediately)
      .background(MTA.surface)
      .navigationTitle("Set up")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.left") { page = 3 } }
        ToolbarItem(placement: .topBarTrailing) { Button("Skip") { finish() } }
        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editorFocused = false } }
      }
    }
  }

  // MARK: - 3 · Building → ready

  private var building: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          MTALabel(summary == nil ? "Step 2 of 2 · building" : "All set")
          Text(summary == nil ? "Building your offline pack" : "You're ready").mta(.displayMedium).foregroundStyle(MTA.text)
          ForEach(PrepareService.Step.allCases, id: \.self) { s in
            HStack(spacing: 14) {
              Milestone(value: done.contains(s) ? "✓" : "\(s.rawValue + 1)", state: state(s))
              Text(s.title).mta(.body1).foregroundStyle(done.contains(s) || current == s ? MTA.text : MTA.text2)
              Spacer()
              if current == s && summary == nil { ProgressView() }
              if done.contains(s) { MTALabel(s == .map || s == .places ? "Cloud" : "Cloud · Gemini", color: MTA.text2) }
            }
          }
          if let error { NoticeCard(text: error) }
          if let summary {
            GridRow4 {
              NumberBox(value: "\(summary.items)", caption: "Bookings")
              NumberBox(value: "\(summary.phrases)", caption: "Phrases")
              NumberBox(value: "\(summary.places)", caption: "Places")
              NumberBox(value: "\(summary.mapAreas)", caption: "Maps", style: summary.mapAreas > 0 ? .status(.onTrack) : .status(.obstacle))
            }
            NoticeCard(text: summary.packError != nil
                       ? "Bookings are saved. The phrase & safety pack didn't finish — get it from the Prepare tab on Wi-Fi."
                       : summary.mapError == nil
                       ? "Everything is on this iPhone now. Turn on Airplane Mode — Ask, Say, the taxi card and the map keep working."
                       : "Bookings and phrases are saved. The offline map didn't finish — try again from the Map tab on Wi-Fi.")
            Button("Start my trip") { if emergencyCards.isEmpty { page = 4 } else { finish() } }.buttonStyle(.mtaPrimary)
          } else if error != nil {
            Button("Try again") { page = 1; error = nil }.buttonStyle(.mtaPrimary)
          }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .background(MTA.surface)
      .navigationTitle("Set up")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private func state(_ s: PrepareService.Step) -> Milestone.State {
    if done.contains(s) { return .done }
    if current == s { return error == nil ? .today : .missed }
    return .upcoming
  }

  private func build() async {
    editorFocused = false
    page = 2; error = nil; done = []; summary = nil
    do {
      let result = try await PrepareService.setUp(from: text, ai: ai) { step in
        if let c = current { done.insert(c) }
        current = step
      }
      if let c = current { done.insert(c) }
      if result.items == 0 { error = "No bookings found in that text."; return }
      summary = result
    } catch {
      self.error = error.localizedDescription
    }
  }

  // MARK: - 4 · Emergency card (last page)

  private var emergencyIntro: some View {
    ZStack {
      MTA.emergency.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 20) {
        Image("StarOfLife").resizable().scaledToFit().padding(12).frame(width: 84, height: 84)
          .background(.white, in: .circle).accessibilityHidden(true)
        Text("One more thing: your emergency card").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
          .fixedSize(horizontal: false, vertical: true)
        Text("If you get sick or hurt abroad, show this card. Your allergies, medicines and blood type, in the local language.")
          .mta(.body1).foregroundStyle(.white)
        VStack(alignment: .leading, spacing: 14) {
          introPoint(1, "About a minute", "Five quick questions, mostly taps")
          introPoint(2, "Health can help", "Blood type and medicines, if you allow it")
          introPoint(3, "Stays on this iPhone", "Never synced; works offline")
        }
        Spacer(minLength: 0)
        Button { settingUpCard = true } label: {
          Text("Set up my card").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.emergency)
            .frame(maxWidth: .infinity, minHeight: 54).background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
        Button("Later") { finish() }.font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
    }
    .fullScreenCover(isPresented: $settingUpCard) {
      EmergencySetupView { _ in settingUpCard = false; finish() }
    }
  }

  private func introPoint(_ n: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(n)").font(.system(size: 16, weight: .semibold)).foregroundStyle(MTA.emergency)
        .frame(width: 36, height: 36).background(.white, in: .circle)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
        Text(detail).mta(.body2).foregroundStyle(.white.opacity(0.85))
      }
    }
  }

  private func finish() {
    onboarded = true
    dismiss()
  }
}
