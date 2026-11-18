import SwiftUI
import SwiftData

/// Settings (pushed from Home's gear — not a tab).
struct SettingsView: View {
  @Environment(AIService.self) private var ai
  @Query private var packs: [DestinationPack]
  @AppStorage("appearance") private var appearance = 0
  @AppStorage("waitForWiFi") private var waitForWiFi = true
  @AppStorage("syncTravelLog") private var syncTravelLog = false

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

        section("Trip")
        MTAValueRow(title: "Home language", value: "English")
        MTAValueRow(title: "Destination", value: packs.first?.countryName ?? "—")

        section("Privacy")
        MTAValueRow(title: "Vault & plans", value: "This iPhone only")
        MTAToggleRow(title: "Sync travel log", isOn: $syncTravelLog)

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
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func section(_ title: String) -> some View { MTALabel(title).padding(.top, 14) }
}
