import Foundation
import FoundationModels
import SwiftData
import SwiftUI

/// What Home shows while the catch-up pass runs (Figma: App Screens → "Catch-up pass · flow").
enum CatchUpState: Equatable {
  case idle
  /// Drafts are waiting: roaming / Low Data with data saver on. Home offers Improve now.
  case waiting(Int)
  case running(Int)
  case done(improved: Int, kept: Int, unchanged: Int, failed: Int)
}

@Generable
struct ReviewedTranslation {
  @Guide(description: "The best translation, in the target language's native script. If the draft is already good, return it unchanged.")
  var translation: String
  @Guide(description: "true only if you changed the draft")
  var changed: Bool
  @Guide(description: "If changed: one short line in English saying what changed, for the traveler (e.g. 'Full polite sentence'). Empty if unchanged.")
  var whatChanged: String
}

/// Catch-up pass: translations made on the phone are drafts. When a good connection is back,
/// Gemini reviews each draft. Code (not AI) checks that numbers and medicine names stay the same;
/// if they don't, the draft is kept and marked "Check this". Every step is written to the Log.
@MainActor
enum CatchUpService {
  static let batch = 10
  private static var running = false

  /// Drafts still to review, oldest first.
  static func pending(_ context: ModelContext) -> [TranslationEntry] {
    let all = (try? context.fetch(FetchDescriptor<TranslationEntry>(
      predicate: #Predicate { $0.isDraft }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    return all.filter { $0.checkReason == nil && $0.polishedTranslation == nil }
  }

  /// `manual`: the traveler tapped Improve now (allowed on mobile data).
  @discardableResult
  static func run(ai: AIService, manual: Bool = false, pack: DestinationPack?) async -> CatchUpState {
    guard !running else { return ai.catchUp }
    let drafts = Array(pending(ai.context).prefix(batch))
    guard !drafts.isEmpty else { ai.catchUp = .idle; return .idle }
    let kind: TaskKind = manual ? .catchUpNow : .catchUp
    switch RoutingPolicy.decide(kind, ai.routingContext) {
    case .run: break
    case .deferToWiFi, .blocked:
      ai.catchUp = .waiting(drafts.count)
      return ai.catchUp
    }

    running = true
    defer { running = false }
    ai.catchUp = .running(drafts.count)
    ai.note("Catch-up · start", kind, reason: manual ? "You tapped Improve now" : "Back online",
            outcome: "ok", note: "\(drafts.count) draft\(drafts.count == 1 ? "" : "s") to check")

    var improved = 0, kept = 0, unchanged = 0, failed = 0
    let language = pack?.languageName ?? "the local language"
    for entry in drafts {
      let (from, to) = entry.direction == "out" ? ("English", language) : (language, "English")
      do {
        let (review, meta) = try await ai.generate(
          "Catch-up · translate", kind: kind,
          prompt: Prompts.review(entry, from: from, to: to),
          instructions: Prompts.reviewInstructions(from: from, to: to),
          as: ReviewedTranslation.self)
        let new = review.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !review.changed || new.isEmpty || new == entry.translation {
          entry.isDraft = false
          entry.polishedTranslation = entry.translation
          entry.improvedAt = .now
          entry.improvedLatencyMs = meta.latencyMs
          ai.lastEntry?.outcome = "unchanged"
          ai.lastEntry?.note = "Draft was already good"
          unchanged += 1
        } else if let problem = SafetyCheck.problem(draft: entry.translation, improved: new, source: entry.sourceText) {
          entry.checkReason = problem
          ai.lastEntry?.outcome = "kept"
          ai.lastEntry?.note = "Draft kept: \(problem)"
          kept += 1
        } else {
          entry.draftTranslation = entry.translation
          entry.translation = new
          entry.polishedTranslation = new
          entry.whatChanged = review.whatChanged.isEmpty ? nil : review.whatChanged
          entry.romanization = entry.direction == "out" ? Romanizer.latin(new, languageCode: pack?.languageCode) : ""
          entry.isDraft = false
          entry.source = "inCloud"
          entry.improvedAt = .now
          entry.improvedLatencyMs = meta.latencyMs
          ai.lastEntry?.outcome = "improved"
          ai.lastEntry?.note = review.whatChanged.isEmpty ? "Improved" : review.whatChanged
          improved += 1
        }
      } catch {
        // Stays a draft; the next pass retries it.
        failed += 1
      }
      try? ai.context.save()
    }
    ai.catchUp = .done(improved: improved, kept: kept, unchanged: unchanged, failed: failed)
    return ai.catchUp
  }
}

/// Deterministic check between a draft and the cloud's version: numbers (doses, times, prices)
/// and medicine names written in Latin letters must be identical. Never an AI judgment.
enum SafetyCheck {
  static func problem(draft: String, improved: String, source: String) -> String? {
    let a = numbers(draft), b = numbers(improved)
    if a != b {
      return "a number changed (\(a.joined(separator: ", ").nilIfEmpty ?? "none") → \(b.joined(separator: ", ").nilIfEmpty ?? "none"))"
    }
    // Every number the traveler wrote must still be there.
    let missing = numbers(source).filter { !b.contains($0) }
    if !missing.isEmpty { return "a number you wrote is missing (\(missing.joined(separator: ", ")))" }
    // Latin words in the draft (e.g. "(ibuprofen)") must survive.
    let lost = latinWords(draft).subtracting(latinWords(improved))
    if !lost.isEmpty { return "a name changed (\(lost.sorted().joined(separator: ", ")))" }
    return nil
  }

  /// "200mg", "２００" → ["200"]. Full-width digits are folded to ASCII.
  static func numbers(_ s: String) -> [String] {
    let folded = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
    return folded.matches(of: /\d+(?:[.,]\d+)?/).map { String($0.output) }.sorted()
  }

  static func latinWords(_ s: String) -> Set<String> {
    Set(s.matches(of: /[A-Za-z]{3,}/).map { $0.output.lowercased() })
  }
}

extension Prompts {
  static func reviewInstructions(from: String, to: String) -> String {
    """
    You review a draft translation from \(from) into \(to) that a small on-device model made for a traveler. \
    Make it natural and polite, as a local would say it, in \(to)'s native script. \
    Never change meaning, numbers, doses or medicine names; keep any English medicine name in parentheses. \
    If the draft is already good, return it unchanged with changed = false.
    """
  }

  static func review(_ e: TranslationEntry, from: String, to: String) -> String {
    var lines = ["Original (\(from)): \(e.sourceText)", "Draft (\(to)): \(e.translation)"]
    if let s = e.situation { lines.insert("Situation: \(s)", at: 0) }
    return lines.joined(separator: "\n")
  }
}

/// "Back online · improving 3 translations…" → "2 improved · 1 kept for you to check". Hides itself.
struct CatchUpToast: View {
  @Environment(AIService.self) private var ai

  var body: some View {
    Group {
      switch ai.catchUp {
      case let .running(n):
        toast(MTA.accent, "Back online · improving \(n) translation\(n == 1 ? "" : "s")…", "Gemini checks your offline drafts")
      case let .done(improved, kept, unchanged, failed):
        toast(kept > 0 || failed > 0 ? MTA.obstacle : MTA.onTrack, Self.summary(improved, kept, unchanged, failed), "See the Log for each one")
          .task {
            try? await Task.sleep(for: .seconds(4))
            if case .done = ai.catchUp { withAnimation(.snappy) { ai.catchUp = .idle } }
          }
      default:
        EmptyView()
      }
    }
    .animation(.snappy, value: ai.catchUp)
  }

  static func summary(_ improved: Int, _ kept: Int, _ unchanged: Int, _ failed: Int) -> String {
    var parts: [String] = []
    if improved > 0 { parts.append("\(improved) improved") }
    if unchanged > 0 { parts.append("\(unchanged) already good") }
    if kept > 0 { parts.append("\(kept) kept for you to check") }
    if failed > 0 { parts.append("\(failed) will retry") }
    return parts.isEmpty ? "Translations checked" : parts.joined(separator: " · ")
  }

  private func toast(_ dot: Color, _ title: String, _ sub: String) -> some View {
    HStack(spacing: 10) {
      Circle().fill(dot).frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        Text(sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
      }
    }
    .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 12)
    .background(.black, in: .capsule)
    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityElement(children: .combine)
  }
}
