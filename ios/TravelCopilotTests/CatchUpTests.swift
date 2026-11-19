import Foundation
import SwiftData
import Testing
@testable import TravelCopilot

@MainActor
struct CatchUpTests {
  @Test func safeImprovementPasses() {
    #expect(SafetyCheck.problem(draft: "ペニシリンのアレルギーです。",
                                improved: "ペニシリン (penicillin) にアレルギーがあります。",
                                source: "I'm allergic to penicillin") == nil)
  }

  @Test func changedDoseKeepsTheDraft() throws {
    let why = try #require(SafetyCheck.problem(draft: "イブプロフェン (ibuprofen) を200mg飲んでいます。",
                                               improved: "イブプロフェン (ibuprofen) を2錠飲んでいます。",
                                               source: "I take 200 mg of ibuprofen"))
    #expect(why.contains("200"))
  }

  @Test func lostMedicineNameKeepsTheDraft() {
    #expect(SafetyCheck.problem(draft: "イブプロフェン (ibuprofen) を200mg",
                                improved: "イブプロフェンを200mg", source: "200 mg ibuprofen") != nil)
  }

  @Test func fullWidthDigitsCountAsTheSameNumber() {
    #expect(SafetyCheck.numbers("２００mg") == ["200"])
    #expect(SafetyCheck.problem(draft: "200mg", improved: "２００mg", source: "200 mg") == nil)
  }

  @Test func improveNowRunsOnMobileDataButNotOffline() {
    let roaming = RoutingContext(isOnline: true, isExpensive: true, isConstrained: false, deviceModelAvailable: true)
    #expect(RoutingPolicy.decide(.catchUp, roaming) == .deferToWiFi(reason: "Roaming data saver → waiting for Wi-Fi"))
    guard case .run(.cloudOnly, _) = RoutingPolicy.decide(.catchUpNow, roaming) else { Issue.record("should run"); return }
    var offline = roaming; offline.isOnline = false
    guard case .deferToWiFi = RoutingPolicy.decide(.catchUpNow, offline) else { Issue.record("should wait"); return }
  }

  @Test func onlyUncheckedDraftsArePicked() throws {
    let container = try ModelContainer(for: TranslationEntry.self, configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    func add(_ t: String, draft: Bool, kept: Bool = false, at: Double) {
      let e = TranslationEntry(sourceText: t, translation: t, direction: "out", languageCode: "ja", source: "onDevice", isDraft: draft)
      e.createdAt = Date(timeIntervalSince1970: at)
      if kept { e.checkReason = "a number changed" }
      ctx.insert(e)
    }
    add("b", draft: true, at: 2); add("a", draft: true, at: 1); add("cloud", draft: false, at: 0); add("kept", draft: true, kept: true, at: 3)
    #expect(CatchUpService.pending(ctx).map(\.sourceText) == ["a", "b"])
  }

  @Test func toastSummary() {
    #expect(CatchUpToast.summary(2, 1, 0, 0) == "2 improved · 1 kept for you to check")
    #expect(CatchUpToast.summary(0, 0, 3, 0) == "3 already good")
  }
}
