import Foundation
import SwiftData

/// One booking, stored as structured fields. The on-device model never invents
/// these values: it only picks which field answers a question (plan §2, trust rule).
@Model
final class VaultItem {
  var kind: String              // flight · hotel · train · other
  var title: String
  var confirmationCode: String?
  var startDate: String?        // yyyy-MM-dd as written in the booking
  var endDate: String?
  var checkInTime: String?
  var checkOutTime: String?
  var departureTime: String?
  var arrivalTime: String?
  var origin: String?
  var destination: String?
  var address: String?
  /// Address in the destination's local script, for the taxi Big-Card.
  var addressLocal: String?
  /// True when `addressLocal` was translated by AI rather than copied from the booking.
  var addressLocalIsAIGenerated: Bool = false
  var phone: String?
  var countryCode: String?
  var createdAt: Date = Date()

  init(kind: String, title: String) {
    self.kind = kind
    self.title = title
  }

  var symbol: String {
    switch kind {
    case "flight": "airplane"
    case "hotel": "bed.double.fill"
    case "train": "tram.fill"
    default: "doc.text.fill"
    }
  }
}

struct Phrase: Codable, Hashable, Sendable {
  var situation: String
  var english: String
  var local: String
  var romanization: String
}

/// Everything the traveler needs offline for one country, built in the cloud during Prepare.
@Model
final class DestinationPack {
  var countryCode: String
  var countryName: String
  var languageName: String
  var languageCode: String
  /// "Please take me to this address" in the local language.
  var taxiLine: String
  var phrases: [Phrase] = []
  var scams: [String] = []
  var createdAt: Date = Date()

  init(countryCode: String, countryName: String, languageName: String, languageCode: String, taxiLine: String) {
    self.countryCode = countryCode
    self.countryName = countryName
    self.languageName = languageName
    self.languageCode = languageCode
    self.taxiLine = taxiLine
  }
}

/// A translation made during the trip. On-device results are drafts that the
/// Catch-up pass re-translates in the cloud.
@Model
final class TranslationEntry {
  var createdAt: Date = Date()
  var sourceText: String
  var translation: String
  var romanization: String = ""
  var note: String = ""
  /// "out" = traveler → local language, "in" = local's reply → traveler.
  var direction: String
  var languageCode: String
  var situation: String?
  var source: String            // onDevice · inCloud
  var latencyMs: Int = 0
  var isDraft: Bool
  var polishedTranslation: String?

  init(sourceText: String, translation: String, direction: String, languageCode: String,
       source: String, isDraft: Bool) {
    self.sourceText = sourceText
    self.translation = translation
    self.direction = direction
    self.languageCode = languageCode
    self.source = source
    self.isDraft = isDraft
  }
}

/// Something the traveler planned for a trip day. Stored only on this iPhone; works offline.
@Model
final class TripPlan {
  var start: Date
  var title: String
  var detail: String = ""
  /// user · booking · suggested (suggestions need Wi-Fi and are labeled)
  var source: String = "user"
  var remind: Bool = true
  var createdAt: Date = Date()

  init(start: Date, title: String, detail: String = "", source: String = "user") {
    self.start = start
    self.title = title
    self.detail = detail
    self.source = source
  }
}

/// A point on the trip map: the hotel, an airport, or a planned place.
/// Coordinates are looked up once online (Prepare / Download map) and then work offline.
@Model
final class Place {
  var name: String
  /// hotel · airport · plan
  var kind: String
  var latitude: Double
  var longitude: Double
  var address: String = ""
  /// booking · you
  var source: String = "booking"
  var createdAt: Date = Date()

  init(name: String, kind: String, latitude: Double, longitude: Double, address: String = "", source: String = "booking") {
    self.name = name
    self.kind = kind
    self.latitude = latitude
    self.longitude = longitude
    self.address = address
    self.source = source
  }

  var symbol: String {
    switch kind { case "hotel": "bed.double.fill"; case "airport": "airplane"; default: "mappin" }
  }
}

/// A map area saved for offline use: snapshot images (Day + Night) and the region they cover.
@Model
final class MapPack {
  var name: String              // "Around your hotel" · "Whole trip"
  var centerLatitude: Double
  var centerLongitude: Double
  var spanLatitude: Double
  var spanLongitude: Double
  @Attribute(.externalStorage) var dayImage: Data?
  @Attribute(.externalStorage) var nightImage: Data?
  var createdAt: Date = Date()

  init(name: String, centerLatitude: Double, centerLongitude: Double, spanLatitude: Double, spanLongitude: Double) {
    self.name = name
    self.centerLatitude = centerLatitude
    self.centerLongitude = centerLongitude
    self.spanLatitude = spanLatitude
    self.spanLongitude = spanLongitude
  }
}

/// One AI request (or a request the policy deferred/blocked), for the Routing Log.
@Model
final class RoutingEntry {
  var timestamp: Date = Date()
  var task: String
  var kind: String
  var requestedRoute: String?   // hybrid · deviceOnly · cloudOnly · nil when not run
  var source: String?           // onDevice · inCloud
  var latencyMs: Int = 0
  var reason: String
  var outcome: String           // ok · error · deferred · blocked
  var detail: String?
  var network: String

  init(task: String, kind: TaskKind, reason: String, outcome: String, network: String) {
    self.task = task
    self.kind = kind.rawValue
    self.reason = reason
    self.outcome = outcome
    self.network = network
  }
}

/// One message in Blue's chat, saved so the conversation is still there next time.
/// Answers are stored as what was shown (values copied from bookings), never regenerated.
@Model
final class ChatMessage {
  var createdAt: Date
  var role: String          // you · blue
  var kind: String          // text · vault · place · notInVault · other · translation · error
  var text: String          // your question, or Blue's sentence
  var value: String = ""    // big value ("15:00", "830 m", the translation)
  var subtitle: String = "" // day, estimate, or romanization
  var note: String = ""
  var sourceTitle: String = ""
  var sourceRef: String = ""
  var sourceSymbol: String = ""
  var caption: String = ""  // "On-device · 4.1 s · From your booking"
  var link: String = ""     // taxi:<booking title> · map · translation:<translation>

  init(role: String, kind: String, text: String, createdAt: Date = .now) {
    self.role = role; self.kind = kind; self.text = text; self.createdAt = createdAt
  }
}
