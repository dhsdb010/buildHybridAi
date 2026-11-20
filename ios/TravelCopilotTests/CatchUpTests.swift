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

@MainActor
struct IDRepairTests {
  @Test func repeatedIdsGetFreshOnes() throws {
    let container = try ModelContainer(for: VaultItem.self, TranslationEntry.self, configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let a = VaultItem(kind: "hotel", title: "Same Hotel"), b = VaultItem(kind: "hotel", title: "Same Hotel")
    b.uid = a.uid
    let t1 = TranslationEntry(sourceText: "x", translation: "x", direction: "out", languageCode: "ja", source: "onDevice", isDraft: true)
    let t2 = TranslationEntry(sourceText: "y", translation: "y", direction: "out", languageCode: "ja", source: "onDevice", isDraft: true)
    t2.uid = t1.uid
    [a, b].forEach(ctx.insert); [t1, t2].forEach(ctx.insert)
    IDRepair.run(ctx)
    #expect(a.uid != b.uid)
    #expect(t1.uid != t2.uid)
  }
}

struct NoteLanguageTests {
  @Test func notesMustBeEnglish() {
    #expect(AIService.isMostlyLatin("Please mention your allergy clearly."))
    #expect(!AIService.isMostlyLatin("日本の薬局では、処方箋があれば医師の指示に従って服用することが大切です。"))
    #expect(AIService.isMostlyLatin(""))
  }
}

@MainActor
struct RoutingLogTests {
  @Test func keepsOnlyTheNewestRows() throws {
    let container = try ModelContainer(for: RoutingEntry.self, configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    for i in 0..<10 {
      let e = RoutingEntry(task: "t\(i)", kind: .survive, reason: "r", outcome: "ok", network: "wifi")
      e.timestamp = Date(timeIntervalSince1970: Double(i))
      ctx.insert(e)
    }
    RoutingLog.trim(ctx, keep: 4)
    let left = try ctx.fetch(FetchDescriptor<RoutingEntry>(sortBy: [SortDescriptor(\.timestamp)])).map(\.task)
    #expect(left == ["t6", "t7", "t8", "t9"])
  }

  @Test func csvQuotesCommasAndQuotes() {
    let e = RoutingEntry(task: "Catch-up · translate", kind: .catchUp, reason: "Good connection → cloud catch-up", outcome: "improved", network: "wifi")
    e.source = "inCloud"; e.latencyMs = 1336; e.note = "Said \"hello\", politely"
    let lines = RoutingLog.csv([e]).split(separator: "\n")
    #expect(lines[0] == "time,task,kind,route_requested,ran_on,latency_ms,outcome,network,reason,note,error")
    #expect(lines[1].hasSuffix(",inCloud,1336,improved,wifi,Good connection → cloud catch-up,\"Said \"\"hello\"\", politely\","))
  }
}
