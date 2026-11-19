import AppIntents
import Foundation

/// "Done" on the Live Activity: marks the current step finished and moves the journey on.
/// A LiveActivityIntent runs in the app's process, where `JourneyIntentHandler.done` is set.
struct JourneyDoneIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Mark step done"
  static let description = IntentDescription("Tells Travel Copilot this step of the trip is finished.")

  @Parameter(title: "Step") var stepID: String

  init() { stepID = "" }
  init(stepID: String) { self.stepID = stepID }

  func perform() async throws -> some IntentResult {
    await JourneyIntentHandler.run(stepID)
    return .result()
  }
}

@MainActor
enum JourneyIntentHandler {
  /// Set by the app at launch. Never set in the widget extension.
  static var done: (@MainActor (String) async -> Void)?
  static func run(_ id: String) async { await done?(id) }
}
