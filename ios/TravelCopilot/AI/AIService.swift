import CoreLocation
import Foundation
import FirebaseAILogic
import FoundationModels
import Observation
import SwiftData

enum AIServiceError: LocalizedError {
  case blocked(String)
  case deferred(String)

  var errorDescription: String? {
    switch self {
    case let .blocked(reason): reason
    case let .deferred(reason): "Saved for later: \(reason)"
    }
  }
}

struct AIMeta: Sendable {
  let route: Route
  let source: InferenceSource
  let latencyMs: Int
}

/// App-level entry point for AI work: asks `RoutingPolicy` where a task should run,
/// runs it through `ModelRouter` (Firebase AI Logic), and records every call in the Routing Log.
@MainActor
@Observable
final class AIService {
  let connectivity: Connectivity
  let context: ModelContext
  var dataSaver = true
  /// The last Log row written, so a caller can add the result (catch-up: improved / kept).
  private(set) var lastEntry: RoutingEntry?
  /// Catch-up pass progress, shown on Home.
  var catchUp: CatchUpState = .idle

  init(connectivity: Connectivity, context: ModelContext) {
    self.connectivity = connectivity
    self.context = context
  }

  var deviceModelAvailable: Bool { ModelRouter.systemModel.isAvailable }

  var routingContext: RoutingContext {
    RoutingContext(
      isOnline: connectivity.isOnline,
      isExpensive: connectivity.isExpensive,
      isConstrained: connectivity.isConstrained,
      deviceModelAvailable: deviceModelAvailable,
      dataSaver: dataSaver)
  }

  private var networkLabel: String {
    guard connectivity.isOnline else { return "offline" }
    return connectivity.interface + (connectivity.isExpensive ? " 💸" : "")
      + (connectivity.isConstrained ? " (low data)" : "")
  }

  /// Structured generation. Works on both routes: `@Generable` on-device, JSON schema in the cloud.
  func generate<T: Generable>(
    _ task: String, kind: TaskKind, prompt: String, instructions: String? = nil, as type: T.Type
  ) async throws -> (T, AIMeta) {
    let route = try resolveRoute(task, kind: kind)
    let start = ContinuousClock.now
    do {
      let session = try ModelRouter.session(for: route.route, instructions: instructions)
      let response = try await session.respond(to: prompt, generating: T.self)
      let meta = AIMeta(
        route: route.route, source: ModelRouter.source(of: response.rawResponse),
        latencyMs: (ContinuousClock.now - start).milliseconds)
      log(task, kind, reason: route.reason, outcome: "ok", meta: meta)
      return (response.content, meta)
    } catch {
      log(task, kind, reason: route.reason, outcome: "error", route: route.route,
          latencyMs: (ContinuousClock.now - start).milliseconds, detail: String(describing: error))
      throw error
    }
  }

  /// Cloud-only call with Grounding with Google Maps. Returns the model's text plus the Maps
  /// grounding chunks (real places: title, Maps link, place ID). Callers must only show places
  /// that appear in `places`, never names that exist only in the text.
  func grounded(
    _ task: String, prompt: String, instructions: String, near: CLLocationCoordinate2D?
  ) async throws -> (text: String, places: [GoogleMapsGroundingChunk], meta: AIMeta) {
    let route = try resolveRoute(task, kind: .prepare)
    guard TravelCopilotApp.firebaseConfigured else { throw ModelRouter.NotConfigured() }
    let start = ContinuousClock.now
    do {
      let model = FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
        modelName: ModelRouter.cloudModelName,
        tools: [.googleMaps()],
        toolConfig: near.map { ToolConfig(retrievalConfig: RetrievalConfig(location: $0)) },
        systemInstruction: ModelContent(role: "system", parts: instructions))
      let response = try await model.generateContent(prompt)
      let chunks = response.candidates.first?.groundingMetadata?.groundingChunks.compactMap(\.maps) ?? []
      let meta = AIMeta(route: .cloudOnly, source: .inCloud, latencyMs: (ContinuousClock.now - start).milliseconds)
      log(task, .prepare, reason: route.reason + " · Google Maps", outcome: "ok", meta: meta)
      return (response.text ?? "", chunks, meta)
    } catch {
      log(task, .prepare, reason: route.reason, outcome: "error", route: .cloudOnly,
          latencyMs: (ContinuousClock.now - start).milliseconds, detail: String(describing: error))
      throw error
    }
  }

  private func resolveRoute(_ task: String, kind: TaskKind) throws -> (route: Route, reason: String) {
    switch RoutingPolicy.decide(kind, routingContext) {
    case let .run(route, reason):
      return (route, reason)
    case let .deferToWiFi(reason):
      log(task, kind, reason: reason, outcome: "deferred")
      throw AIServiceError.deferred(reason)
    case let .blocked(reason):
      log(task, kind, reason: reason, outcome: "blocked")
      throw AIServiceError.blocked(reason)
    }
  }

  private func log(_ task: String, _ kind: TaskKind, reason: String, outcome: String,
                   meta: AIMeta? = nil, route: Route? = nil, latencyMs: Int = 0, detail: String? = nil) {
    let entry = RoutingEntry(task: task, kind: kind, reason: reason, outcome: outcome, network: networkLabel)
    entry.requestedRoute = (meta?.route ?? route)?.rawValue
    entry.source = meta.map { $0.source == .onDevice ? "onDevice" : "inCloud" }
    entry.latencyMs = meta?.latencyMs ?? latencyMs
    entry.detail = detail
    context.insert(entry)
    try? context.save()
    lastEntry = entry
    inserted += 1
    if inserted % 50 == 0 { RoutingLog.compact(context) }
  }

  private var inserted = 0

  /// A Log row that isn't an AI call (e.g. "Catch-up · start: back online → 3 drafts").
  func note(_ task: String, _ kind: TaskKind, reason: String, outcome: String, note: String? = nil) {
    log(task, kind, reason: reason, outcome: outcome)
    lastEntry?.note = note
    try? context.save()
  }
}
