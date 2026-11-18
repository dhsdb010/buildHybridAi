import SwiftUI
import FirebaseAILogic
import FoundationModels

/// Day-1 risk spike. Answers four questions on a real device:
/// 1. Does on-device inference work in Airplane Mode with App Check enforced?
/// 2. Can we tell on-device from cloud on each response?
/// 3. Does structured output (@Generable) work on-device?
/// 4. What do isExpensive / isConstrained report on cellular and Low Data Mode?
struct SpikeView: View {
  @Environment(Connectivity.self) private var net
  @State private var prompt = "Translate to Japanese, politely: Where is the nearest pharmacy?"
  @State private var log: [LogEntry] = []
  @State private var busy = false

  var body: some View {
    NavigationStack {
      List {
        Section("Status") {
          row("Firebase configured", TravelCopilotApp.firebaseConfigured ? "✅" : "❌ add GoogleService-Info.plist")
          row("On-device model", availabilityText)
          row("Network", net.isOnline ? "online (\(net.interface))" : "offline")
          row("isExpensive", net.isExpensive ? "yes 💸" : "no")
          row("isConstrained", net.isConstrained ? "yes (Low Data)" : "no")
        }
        Section("Prompt") {
          TextField("Prompt", text: $prompt, axis: .vertical).lineLimit(2...5)
          ForEach(Route.allCases, id: \.self) { route in
            Button("Run .\(route.rawValue)") { run(route) }.disabled(busy)
          }
          Button("Structured output (.deviceOnly)") { runStructured() }.disabled(busy)
        }
        Section("Results") {
          if busy { ProgressView() }
          ForEach(log.reversed()) { entry in
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.header).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(entry.body).font(.body).textSelection(.enabled)
            }
          }
        }
      }
      .navigationTitle("Day-1 Spike")
    }
  }

  private var availabilityText: String {
    switch ModelRouter.systemModel.availability {
    case .available: return "✅ available"
    case .unavailable(let reason): return "❌ \(reason)"
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    LabeledContent(label, value: value)
  }

  private var networkTag: String {
    net.isOnline ? "\(net.interface)\(net.isExpensive ? " 💸" : "")" : "OFFLINE"
  }

  private func run(_ route: Route) {
    busy = true
    let tag = networkTag
    Task {
      defer { busy = false }
      do {
        let r = try await ModelRouter.run(prompt, route: route)
        log.append(LogEntry(
          header: ".\(route.rawValue) · \(tag) → \(r.source.rawValue) · \(r.latencyMs) ms · \(r.modelVersion)",
          body: r.text))
      } catch {
        log.append(LogEntry(header: ".\(route.rawValue) · \(tag) → ❌ error", body: String(describing: error)))
      }
    }
  }

  private func runStructured() {
    busy = true
    let tag = networkTag
    Task {
      defer { busy = false }
      let start = ContinuousClock.now
      do {
        let session = try ModelRouter.session(for: .deviceOnly)
        let response = try await session.respond(
          to: "Classify this traveler question about their bookings: \"What time can I check in?\"",
          generating: VaultQuery.self)
        let ms = (ContinuousClock.now - start).milliseconds
        log.append(LogEntry(
          header: "structured · \(tag) → \(ModelRouter.source(of: response.rawResponse).rawValue) · \(ms) ms",
          body: "item=\(response.content.item) field=\(response.content.field)"))
      } catch {
        log.append(LogEntry(header: "structured · \(tag) → ❌ error", body: String(describing: error)))
      }
    }
  }
}

/// Spike version of the Vault question classifier from the plan's trust rule.
@Generable
struct VaultQuery {
  @Guide(description: "Which booking the question is about", .anyOf(["flight", "hotel", "train", "unknown"]))
  var item: String
  @Guide(description: "Which stored field answers it", .anyOf(["checkInTime", "checkOutTime", "address", "confirmationCode", "departureTime", "unknown"]))
  var field: String
}

struct LogEntry: Identifiable {
  let id = UUID()
  let header: String
  let body: String
}
