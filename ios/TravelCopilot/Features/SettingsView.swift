import SwiftUI
import SwiftData

/// Settings (pushed from Home's gear — not a tab).
struct SettingsView: View {
  @Environment(AIService.self) private var ai
  @Environment(AuthService.self) private var auth
  @Query private var packs: [DestinationPack]
  @State private var confirmDelete = false
  @State private var deleted = false
  @AppStorage("appearance") private var appearance = 0
  @AppStorage("waitForWiFi") private var waitForWiFi = true
  @AppStorage(TripIcon.styleKey) private var iconStyle = TripIcon.Style.symbol.rawValue

  var body: some View {
    @Bindable var ai = ai
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Text("Settings").mta(.displayMedium).foregroundStyle(MTA.text).padding(.bottom, 6)

        section("Network")
        MTAToggleRow(title: "Data saver when roaming", isOn: $ai.dataSaver)
        MTAToggleRow(title: "Wait for Wi-Fi to catch up", isOn: $waitForWiFi)
        MTAValueRow(title: "Cloud model", value: ModelRouter.cloudModelName)
        MTAValueRow(title: "On-device model", value: ai.deviceModelAvailable ? "Available" : "Unavailable")

        section("Appearance")
        MTASegmented(options: ["Auto", "Day", "Night"], selection: $appearance).padding(.vertical, 6)
        Text("Icons").mta(.body1).foregroundStyle(MTA.text).padding(.top, 6)
        MTASegmented(options: ["Symbols", "Emoji"], selection: Binding(
          get: { iconStyle == TripIcon.Style.emoji.rawValue ? 1 : 0 },
          set: { iconStyle = $0 == 1 ? TripIcon.Style.emoji.rawValue : TripIcon.Style.symbol.rawValue })
        ).padding(.vertical, 6)
        HStack(spacing: 8) {
          ForEach(["fork.knife", "bag", "building.columns", "bed.double", "tram", "airplane.departure", "staroflife"], id: \.self) {
            TripIcon(symbol: $0, size: 30)
          }
        }

        section("Trip")
        MTAValueRow(title: "Home language", value: "English")
        MTAValueRow(title: "Destination", value: packs.first?.countryName ?? "—")

        section("Privacy")
        MTAValueRow(title: "Vault & plans", value: "This iPhone only")
        MTAValueRow(title: "Routing Log", value: "This iPhone only")

        section("Account")
        if let account = auth.account {
          MTAValueRow(title: "Signed in with \(account.provider)", value: account.email.isEmpty ? account.name : account.email)
          if let e = auth.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent).fixedSize(horizontal: false, vertical: true) }
          Button("Sign out") { auth.signOut() }
            .buttonStyle(.mtaSecondary).padding(.top, 6)
          Button("Delete account") { confirmDelete = true }
            .mta(.button2).foregroundStyle(MTA.urgent).frame(maxWidth: .infinity, minHeight: 44)
            .disabled(auth.busy)
        } else {
          MTAValueRow(title: "Not signed in", value: "Needed only to plan")
          if deleted { Text("Your account is deleted.").mta(.body2).foregroundStyle(MTA.text2) }
        }

        #if DEBUG
          section("Developer")
          NavigationLink { SpikeView() } label: {
            HStack { Text("Hybrid routing spike").mta(.body1).foregroundStyle(MTA.text); Spacer(); Image(systemName: "chevron.right").foregroundStyle(MTA.text2) }
              .frame(minHeight: 52)
          }
        #endif
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 24)
    }
    .scrollIndicators(.hidden)
    .background(MTA.surface)
    .overlay { if auth.busy { ProgressView() } }
    .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete account", role: .destructive) { Task { deleted = await auth.deleteAccount() } }
    } message: {
      Text("You'll sign in once more to confirm. Your trip on this iPhone stays; only planning needs an account.")
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func section(_ title: String) -> some View { MTALabel(title).padding(.top, 14) }
}
