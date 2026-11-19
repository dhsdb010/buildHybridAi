import ActivityKit
import Foundation

/// One trip moment on the Lock Screen and in the Dynamic Island (Figma page 02 · Live Activities).
/// Values come only from the Vault and the traveler's own plans (no AI text in a Live Activity).
struct TripActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable, Sendable {
    /// "Check-out 11:00" · "Leave for teamLab 12:30" (noun + time, like a station sign).
    var title: String
    /// Small label above the title: "HOTEL · TOKYO", "PLAN · DAY 3".
    var label: String
    /// One line under the title: hotel name + ref, the plan note.
    var detail: String
    /// SF Symbol inside the status bullet.
    var glyph: String
    var progress: TripProgress
    /// The moment itself; the countdown runs to it with the system timer, so it keeps going offline.
    var start: Date
    /// When the reminder began (for the progress bar).
    var since: Date
    /// Booking ref shown top-right ("HSZ-48213"), like a boarding pass.
    var ref: String = ""
    /// Ends of the track: "SFO" → "HND", or "Now" → "11:00".
    var from: String = "Now"
    var to: String = ""
    /// Bottom strip: what tapping opens ("Show taxi card").
    var action: String = "Open Travel Copilot"

    // Journey (one step at a time toward a goal). Empty `stops` = a single moment.
    /// Start, each step's end, and the goal last ("Narita", "Shinjuku", "Hotel").
    var stops: [String] = []
    /// Segment the vehicle is on (0 = first step); `stops.count - 1` = arrived.
    var segment: Int = 0
    /// How far along the segment the vehicle sits (0…1), set when the app last synced.
    var along: Double = 0
    /// "Step 2 of 3" pieces.
    var step: Int = 0
    var steps: Int = 0
    var arrived: Bool = false
    /// Extra line under the title (arrived: ref and check-out).
    var info: String = ""
    /// Bottom-left button: the card for this step.
    var cardLabel: String = ""
    var cardGlyph: String = "doc.text.fill"
    var cardLink: String = "travelcopilot://trip"
    /// The goal at the end of the track ("bed.double.fill" for the hotel).
    var goalGlyph: String = "bed.double.fill"
    /// Id of the step the Done button finishes.
    var stepID: String = ""
  }

  /// Stable id of the trip moment, so the app updates the same activity instead of adding another.
  var eventID: String
}

extension TripProgress {
  /// Status pill on the Live Activity.
  var pill: String {
    switch self {
    case .done: "Done"
    case .now: "Now"
    case .next, .later: "On track"
    case .soon: "Leave now"
    }
  }

  /// Hex of the status color (Figma "MTA Color"; status colors don't change between Day and Night).
  var hex: UInt32 {
    switch self {
    case .done: 0x969696
    case .now: 0x0050EA
    case .next: 0x139240
    case .soon: 0xFF0000
    case .later: 0x139240
    }
  }
}
