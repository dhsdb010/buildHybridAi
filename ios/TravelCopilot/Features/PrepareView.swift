import SwiftUI
import SwiftData

/// Prepare (online, once): paste confirmation emails → Vault + Destination Pack.
struct PrepareView: View {
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Query(sort: \VaultItem.createdAt) private var items: [VaultItem]
  @Query private var packs: [DestinationPack]
  @State private var text = ""
  @State private var busy = false
  @State private var step: PrepareService.Step?
  @State private var error: String?
  @State private var info: String?
  @State private var packBusy = false
  @State private var showPlan = false
  @FocusState private var editorFocused: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          MTALabel("Before you fly · on Wi-Fi")
          Text("Build your offline pack").mta(.displayMedium).foregroundStyle(MTA.text)

          FeatureCard(label: "Not booked yet?", title: "Help me plan",
                      detail: "Chat with AI: where to go, where to stay, what to eat",
                      systemImage: "asterisk") { showPlan = true }

          MTALabel("Paste booking emails")
          TextEditor(text: $text)
            .focused($editorFocused)
            .mta(.body2)
            .scrollContentBackground(.hidden)
            .frame(height: 140)
            .padding(10)
            .overlay(alignment: .topLeading) {
              if text.isEmpty {
                Text("Flight, hotel or train confirmations…").mta(.body2).foregroundStyle(MTA.text2)
                  .padding(.top, 18).padding(.leading, 15).allowsHitTesting(false)
              }
            }
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }

          MTALabel("What you'll have offline")
          readiness(icon: "tray.full", ok: !items.isEmpty, title: "Bookings in your Vault", value: "\(items.count)")
          readiness(icon: "character.book.closed", ok: !packs.isEmpty,
                    title: packs.first.map { "\($0.countryName) pack · phrases & scams" } ?? "Destination pack",
                    value: packs.first.map { "\($0.phrases.count)" } ?? "—")
          readiness(icon: "phone", ok: packs.contains { EmergencyNumbers.numbers(for: $0.countryCode) != nil },
                    title: "Emergency numbers", value: "Bundled")
          readiness(icon: "iphone", ok: ai.deviceModelAvailable, title: "On-device model",
                    value: ai.deviceModelAvailable ? "Ready" : "Off")

          NoticeCard(text: net.isOnline
                     ? "Prepare runs once in the cloud (Gemini). After that, Ask, Say and the taxi card work with no signal."
                     : "You're offline. Prepare needs internet — connect to Wi-Fi to build your pack.")
          if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
          if let info { Text(info).mta(.body2).foregroundStyle(MTA.text2) }

          // Bookings saved but no pack yet (the pack call failed): get just the pack, no re-paste.
          if !items.isEmpty, packs.isEmpty, PrepareService.mainCountry(of: items) != nil {
            Button { Task { await retryPack() } } label: {
              HStack(spacing: 10) {
                if packBusy { ProgressView() }
                Text(packBusy ? PrepareService.Step.pack.title + "…" : "Get the phrase & safety pack")
              }
            }
            .buttonStyle(.mtaSecondary)
            .disabled(busy || packBusy || !net.isOnline)
          }

          Button {
            Task { await run() }
          } label: {
            HStack(spacing: 10) {
              if busy { ProgressView().tint(MTA.onColor) }
              Text(busy ? (step?.title ?? "Working") + "…" : "Build my offline pack")
            }
          }
          .buttonStyle(.mtaPrimary)
          .disabled(text.isEmpty || busy || !net.isOnline)
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.immediately)
      .background(MTA.surface)
      .fullScreenCover(isPresented: $showPlan) { PlanView(onClose: { showPlan = false }) }
      .navigationTitle("Prepare")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Sample") { text = PrepareService.sampleEmail } }
        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editorFocused = false } }
      }
      .task {
        #if DEBUG
          // `-autoPrepareSample`: load the sample and run Prepare, for automated checks.
          // `-planAuto` with `-tab prepare`: open the plan chat when a trip already exists (simulator checks).
          if ProcessInfo.processInfo.arguments.contains("-planAuto"), !items.isEmpty { showPlan = true }
          if ProcessInfo.processInfo.arguments.contains("-autoPrepareSample"), items.isEmpty {
            text = PrepareService.sampleEmail
            Task { await run() } // unstructured, so switching tabs doesn't cancel the cloud calls
          }
        #endif
      }
    }
  }

  private func readiness(icon: String, ok: Bool, title: String, value: String) -> some View {
    HStack(spacing: 14) {
      MilestoneSymbol(systemName: ok ? "checkmark" : icon, ok: ok)
      Text(title).mta(.body1).foregroundStyle(MTA.text).frame(maxWidth: .infinity, alignment: .leading)
      MTALabel(value)
    }
  }

  private func run() async {
    editorFocused = false
    busy = true; error = nil; info = nil
    defer { busy = false }
    do {
      let summary = try await PrepareService.setUp(from: text, ai: ai) { step = $0 }
      if summary.items == 0 { error = "No bookings found in that text."; return }
      text = ""
      if summary.alreadySaved > 0 {
        info = summary.alreadySaved == summary.items
          ? "These bookings are already in your Vault."
          : "\(summary.alreadySaved) of \(summary.items) bookings were already in your Vault."
      }
      if let packError = summary.packError {
        error = "Bookings saved. The phrase & safety pack didn't finish: \(packError)"
      } else if let mapError = summary.mapError {
        error = "Bookings saved. Map: \(mapError)"
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func retryPack() async {
    packBusy = true; error = nil; info = nil
    defer { packBusy = false }
    do { try await PrepareService.ensurePack(for: items, ai: ai) }
    catch { self.error = "The phrase & safety pack didn't finish: \(error.localizedDescription)" }
  }
}
