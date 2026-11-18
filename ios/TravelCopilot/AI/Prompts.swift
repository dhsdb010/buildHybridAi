import Foundation
import FoundationModels

// MARK: - Prepare: booking parser (cloud)

@Generable
struct BookingExtraction {
  @Guide(description: "Every flight, hotel or train booking found in the text. Empty if none.")
  var bookings: [ExtractedBooking]
}

/// Every field is a string copied from the source text, or "" when the text doesn't state it.
@Generable
struct ExtractedBooking {
  @Guide(description: "Booking type", .anyOf(["flight", "hotel", "train", "other"]))
  var kind: String
  @Guide(description: "Short title, e.g. hotel name, or airline + flight number + route")
  var title: String
  @Guide(description: "Confirmation / booking / reservation code exactly as written, or empty")
  var confirmationCode: String
  @Guide(description: "Start date (check-in or departure) as yyyy-MM-dd, or empty")
  var startDate: String
  @Guide(description: "End date (check-out or arrival) as yyyy-MM-dd, or empty")
  var endDate: String
  @Guide(description: "Hotel check-in time as HH:mm (24h), or empty")
  var checkInTime: String
  @Guide(description: "Hotel check-out time as HH:mm (24h), or empty")
  var checkOutTime: String
  @Guide(description: "Departure time as HH:mm (24h), or empty")
  var departureTime: String
  @Guide(description: "Arrival time as HH:mm (24h), or empty")
  var arrivalTime: String
  @Guide(description: "Departure airport/station, or empty")
  var origin: String
  @Guide(description: "Arrival airport/station, or empty")
  var destination: String
  @Guide(description: "Full street address as written (hotels), or empty")
  var address: String
  @Guide(description: "The same address in the local script of its country (e.g. Japanese for Japan). Copy it if the text contains it; otherwise translate it. Empty if no address.")
  var addressLocal: String
  @Guide(description: "true if addressLocal was NOT present in the text and you translated it")
  var addressLocalTranslated: Bool
  @Guide(description: "Phone number as written, or empty")
  var phone: String
  @Guide(description: "ISO 3166-1 alpha-2 country code of the hotel or arrival city, e.g. JP")
  var countryCode: String
}

// MARK: - Prepare: destination pack (cloud)

@Generable
struct GeneratedPack {
  @Guide(description: "Country name in English")
  var countryName: String
  @Guide(description: "Main local language name in English")
  var languageName: String
  @Guide(description: "BCP-47 code of that language, e.g. ja")
  var languageCode: String
  @Guide(description: "Polite sentence meaning 'Please take me to this address', written in the local language's native script (e.g. Japanese kana/kanji, never romaji)")
  var taxiLine: String
  @Guide(description: "12 short, polite survival phrases for a traveler in this country")
  var phrases: [GeneratedPhrase]
  @Guide(description: "4 common tourist scams or overcharges in this country, one sentence each, in English")
  var scams: [String]
}

@Generable
struct GeneratedPhrase {
  @Guide(description: "Situation", .anyOf(["arrival", "taxi", "hotel", "restaurant", "pharmacy", "shopping", "help"]))
  var situation: String
  var english: String
  @Guide(description: "The phrase written in the local language's native script (e.g. こんにちは for Japanese). Never romanized.")
  var local: String
  @Guide(description: "Latin-alphabet pronunciation, or empty if the language uses Latin script")
  var romanization: String
}

enum Prompts {
  static let parseBookingInstructions = """
    You extract travel bookings from confirmation emails. Copy values exactly as written. \
    Never guess a confirmation code, time or address: use an empty string when the text doesn't state it.
    """

  static func parseBooking(_ text: String) -> String {
    "Extract every booking from this confirmation text:\n\n\(text)"
  }

  static let destinationPackInstructions = """
    You prepare an offline survival pack for a traveler whose home language is English. \
    Use natural, polite phrasing that locals actually use. \
    Local-language text must be in the language's native writing system (for Japanese: kana and kanji); \
    put the Latin-alphabet pronunciation only in the romanization field.
    """

  static func destinationPack(countryCode: String, city: String) -> String {
    "Build a survival pack for a traveler visiting \(city.isEmpty ? "" : "\(city), ")country code \(countryCode)."
  }
}

extension String {
  /// "" → nil, for model output that uses empty strings for missing fields.
  var nilIfEmpty: String? {
    let t = trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }
}
