import AppIntents
import Foundation

/// "Show emergency card": one action behind Siri, Spotlight, the Action Button and the
/// Control Center control. It opens Travel Copilot straight on the card (works offline).
struct ShowEmergencyCardIntent: AppIntent {
  static let title: LocalizedStringResource = "Show emergency card"
  static let description = IntentDescription("Opens your emergency medical card full screen, in the local language. Works offline.")
  static let openAppWhenRun = true

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    EmergencyIntentHandler.run()
    return .result()
  }
}

/// The app sets `show` once its screens exist; if the action arrives first (a cold launch),
/// it's remembered and the card opens as soon as the app is ready.
@MainActor
enum EmergencyIntentHandler {
  static var show: (@MainActor () -> Void)? {
    didSet { if pending, let show { pending = false; show() } }
  }
  static var pending = false

  static func run() {
    if let show { show() } else { pending = true }
  }
}
