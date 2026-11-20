import AppIntents

/// Siri and Spotlight phrases. Any App Shortcut can also be put on the Action Button
/// (Settings → Action Button → Shortcut → Travel Copilot → Show emergency card).
struct TravelCopilotShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ShowEmergencyCardIntent(),
      phrases: [
        "Show my emergency card in \(.applicationName)",
        "Open my emergency card in \(.applicationName)",
        "\(.applicationName) emergency card",
      ],
      shortTitle: "Emergency card",
      systemImageName: "staroflife.fill")
  }
}
