import Foundation
import SwiftData
import Testing
@testable import TravelCopilot

/// Probe: where do translations actually run in hybrid mode? Real models, so only with
/// TEST_RUNNER_BLUE_EVAL=1. Lines start with `FALLBACK|`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BLUE_EVAL"] == "1"), .serialized)
struct FallbackProbeTests {
  @Test func whereTranslationsRun() async throws {
    let container = try ModelContainer(for: RoutingEntry.self, TranslationEntry.self, configurations: .init(isStoredInMemoryOnly: true))
    let ai = AIService(connectivity: Connectivity(), context: container.mainContext)
    print("FALLBACK|device model available: \(ai.deviceModelAvailable)")
    let thai = DestinationPack(countryCode: "TH", countryName: "Thailand", languageName: "Thai", languageCode: "th", taxiLine: "")
    let japan = DestinationPack(countryCode: "JP", countryName: "Japan", languageName: "Japanese", languageCode: "ja", taxiLine: "")
    let cases: [(String, String, DestinationPack)] = [
      ("Where is the nearest pharmacy?", "out", japan),
      ("Where is the nearest pharmacy?", "out", thai),
      ("ร้านขายยาอยู่ถัดไปทางซ้ายครับ", "in", thai),       // a Thai reply → English
      ("薬局はこの先の左側です。", "in", japan),            // a Japanese reply → English
    ]
    // Longer than the on-device context window (~4,096 tokens): a long notice pasted in to translate.
    let notice = String(repeating: "Guests must return the room key to the front desk before 11:00 on the day of departure. Late check-out is available on request for an extra fee, subject to availability. Breakfast is served from 6:30 to 10:00 on the second floor. Please do not smoke in the rooms; a cleaning fee will be charged. ", count: 160)
    let long: [(String, String, DestinationPack)] = [(notice, "out", japan)]
    for (text, dir, pack) in cases + long {
      do {
        let (e, meta) = try await ai.translate(text, direction: dir, pack: pack)
        print("FALLBACK|\(pack.languageName) \(dir) \(text.count) chars|route \(meta.route.rawValue)|ran \(meta.source == .onDevice ? "device" : "cloud")|\(meta.latencyMs) ms|\(e.translation.prefix(40))")
      } catch {
        print("FALLBACK|\(pack.languageName) \(dir)|error \(String(describing: error).prefix(200))")
      }
    }
  }
}
