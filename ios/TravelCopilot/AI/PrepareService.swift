import Foundation
import SwiftData

/// Prepare stage: turns pasted confirmation emails into Vault items and a Destination Pack.
@MainActor
enum PrepareService {
  struct Result {
    var items: [VaultItem]
    var pack: DestinationPack?
  }

  enum Step: Int, CaseIterable, Sendable {
    case bookings, pack, places, map

    var title: String {
      switch self {
      case .bookings: "Reading your bookings"
      case .pack: "Building your phrase & safety pack"
      case .places: "Finding your places on the map"
      case .map: "Saving the offline map"
      }
    }
  }

  struct Summary {
    var items = 0, phrases = 0, places = 0, mapAreas = 0
    var country: String?
    var mapError: String?
  }

  /// The whole set-up: bookings + pack (cloud), then places + offline map (best-effort; never fails set-up).
  static func setUp(from text: String, ai: AIService, progress: (Step) -> Void) async throws -> Summary {
    progress(.bookings)
    let result = try await prepare(from: text, ai: ai) { progress(.pack) }
    var summary = Summary(items: result.items.count, phrases: result.pack?.phrases.count ?? 0, country: result.pack?.countryName)
    progress(.places)
    let allItems = (try? ai.context.fetch(FetchDescriptor<VaultItem>())) ?? result.items
    let plans = (try? ai.context.fetch(FetchDescriptor<TripPlan>())) ?? []
    await MapService.locate(items: allItems, plans: plans, context: ai.context)
    let places = (try? ai.context.fetch(FetchDescriptor<Place>())) ?? []
    summary.places = places.count
    progress(.map)
    do { summary.mapAreas = try await MapService.download(places: places, context: ai.context).count }
    catch { summary.mapError = error.localizedDescription }
    return summary
  }

  static func prepare(from text: String, ai: AIService, onParsed: () -> Void = {}) async throws -> Result {
    let (extraction, _) = try await ai.generate(
      "parseBooking", kind: .prepare, prompt: Prompts.parseBooking(text),
      instructions: Prompts.parseBookingInstructions, as: BookingExtraction.self)

    let items = extraction.bookings.map(makeItem)
    items.forEach { ai.context.insert($0) }
    try? ai.context.save()
    onParsed()

    // One Destination Pack for the trip's main country (the hotel's, else the first booking's).
    let main = items.first { $0.kind == "hotel" && $0.countryCode != nil } ?? items.first { $0.countryCode != nil }
    guard let code = main?.countryCode else { return Result(items: items, pack: nil) }

    let existing = try? ai.context.fetch(FetchDescriptor<DestinationPack>(predicate: #Predicate { $0.countryCode == code }))
    if let pack = existing?.first { return Result(items: items, pack: pack) }

    let (generated, _) = try await ai.generate(
      "destinationPack", kind: .prepare,
      prompt: Prompts.destinationPack(countryCode: code, city: main?.destination ?? ""),
      instructions: Prompts.destinationPackInstructions, as: GeneratedPack.self)

    let pack = DestinationPack(
      countryCode: code, countryName: generated.countryName, languageName: generated.languageName,
      languageCode: generated.languageCode, taxiLine: generated.taxiLine)
    pack.phrases = generated.phrases.map {
      Phrase(situation: $0.situation, english: $0.english, local: $0.local, romanization: $0.romanization)
    }
    pack.scams = generated.scams
    ai.context.insert(pack)
    try? ai.context.save()
    return Result(items: items, pack: pack)
  }

  private static func makeItem(_ b: ExtractedBooking) -> VaultItem {
    let item = VaultItem(kind: b.kind, title: b.title)
    item.confirmationCode = b.confirmationCode.nilIfEmpty
    item.startDate = b.startDate.nilIfEmpty
    item.endDate = b.endDate.nilIfEmpty
    item.checkInTime = b.checkInTime.nilIfEmpty
    item.checkOutTime = b.checkOutTime.nilIfEmpty
    item.departureTime = b.departureTime.nilIfEmpty
    item.arrivalTime = b.arrivalTime.nilIfEmpty
    item.origin = b.origin.nilIfEmpty
    item.destination = b.destination.nilIfEmpty
    item.address = b.address.nilIfEmpty
    item.addressLocal = b.addressLocal.nilIfEmpty
    item.addressLocalIsAIGenerated = b.addressLocalTranslated
    item.phone = b.phone.nilIfEmpty
    item.countryCode = b.countryCode.nilIfEmpty?.uppercased()
    return item
  }

  /// Fictional sample confirmations for demos and testing.
  static let sampleEmail = """
    From: reservations@example-hotel.test
    Subject: Your reservation is confirmed – Hotel Hoshizora Shinjuku

    Dear Guest,
    Thank you for booking with Hotel Hoshizora Shinjuku.
    Confirmation number: HSZ-48213
    Check-in: Thursday, December 3, 2026 from 15:00
    Check-out: Monday, December 7, 2026 until 11:00
    Address: 4-99-1 Nishi-Shinjuku, Shinjuku-ku, Tokyo 160-0023, Japan (fictional)
    Phone: +81 3-0000-0000

    ----------
    From: noreply@example-air.test
    Subject: E-ticket receipt – Booking reference QX7P2L

    Passenger: TRAVELER/ALEX
    Flight EA 061  San Francisco (SFO) → Tokyo Haneda (HND)
    Departs: Dec 2, 2026 11:40   Arrives: Dec 3, 2026 15:55
    """
}
