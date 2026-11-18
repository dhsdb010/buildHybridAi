import Foundation
import FirebaseAILogic

/// The three ways a request can be sent through Firebase AI Logic.
enum Route: String, CaseIterable, Sendable {
  /// Apple Foundation Models first, Gemini in the cloud as fallback.
  case hybrid
  /// Apple Foundation Models only. Throws if unavailable.
  case deviceOnly
  /// Gemini in the cloud only.
  case cloudOnly
}

enum InferenceSource: String, Sendable {
  case onDevice = "📱 On-device"
  case inCloud = "☁️ Cloud"
}

struct AIResult: Sendable {
  let text: String
  let source: InferenceSource
  let modelVersion: String
  let latencyMs: Int
  let route: Route
}

/// The single gateway to Firebase AI Logic. Every call is single-turn:
/// a fresh `GenerativeModelSession` per request, because sessions keep history.
@MainActor
enum ModelRouter {
  /// Override later from Remote Config.
  static var cloudModelName = "gemini-3.5-flash-lite"

  /// The SDK reports this `modelVersion` for responses from Apple Foundation Models
  /// (`FirebaseAI.SystemLanguageModel.modelName`, internal in the SDK).
  static let systemModelVersion = "apple-foundation-models-system-language-model"

  static var systemModel: FirebaseAI.SystemLanguageModel { .systemModel() }

  static func provider(for route: Route) -> any LanguageModelProvider {
    switch route {
    case .hybrid:
      return .hybridModel(primary: .systemModel(), secondary: .geminiModel(name: cloudModelName))
    case .deviceOnly:
      return FirebaseAI.SystemLanguageModel.systemModel()
    case .cloudOnly:
      return GeminiModelProvider.geminiModel(name: cloudModelName)
    }
  }

  struct NotConfigured: LocalizedError {
    var errorDescription: String? { "Firebase isn't configured: add GoogleService-Info.plist (see SETUP.md)." }
  }

  static func session(for route: Route, instructions: String? = nil) throws -> GenerativeModelSession {
    guard TravelCopilotApp.firebaseConfigured else { throw NotConfigured() }
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    return ai.generativeModelSession(model: provider(for: route), instructions: instructions)
  }

  static func source(of response: GenerateContentResponse) -> InferenceSource {
    response.modelVersion == systemModelVersion ? .onDevice : .inCloud
  }

  static func run(_ prompt: String, route: Route, instructions: String? = nil) async throws
    -> AIResult {
    let start = ContinuousClock.now
    let response = try await session(for: route, instructions: instructions).respond(to: prompt)
    let elapsed = ContinuousClock.now - start
    return AIResult(
      text: response.content,
      source: source(of: response.rawResponse),
      modelVersion: response.rawResponse.modelVersion,
      latencyMs: elapsed.milliseconds,
      route: route
    )
  }
}

extension Duration {
  var milliseconds: Int {
    Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}
