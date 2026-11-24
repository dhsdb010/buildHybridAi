import Foundation

/// Booking times are written in local time where they happen: a flight leaves at 11:40 in San
/// Francisco and lands at 15:55 in Tokyo. The app shows them as written; this table says which
/// time zone each one is in, so reminders and the Live Activity fire at the real moment even
/// while the phone is still on home time (in flight, in airplane mode).
enum TripTimeZones {
  /// Major airports, by IATA code.
  static let airports: [String: String] = [
    // Japan · Korea · China · Taiwan · Hong Kong · Southeast Asia
    "HND": "Asia/Tokyo", "NRT": "Asia/Tokyo", "KIX": "Asia/Tokyo", "ITM": "Asia/Tokyo", "NGO": "Asia/Tokyo",
    "FUK": "Asia/Tokyo", "CTS": "Asia/Tokyo", "OKA": "Asia/Tokyo", "KMQ": "Asia/Tokyo", "SDJ": "Asia/Tokyo", "HIJ": "Asia/Tokyo",
    "ICN": "Asia/Seoul", "GMP": "Asia/Seoul", "PUS": "Asia/Seoul", "CJU": "Asia/Seoul",
    "TPE": "Asia/Taipei", "TSA": "Asia/Taipei", "KHH": "Asia/Taipei",
    "HKG": "Asia/Hong_Kong", "PEK": "Asia/Shanghai", "PKX": "Asia/Shanghai", "PVG": "Asia/Shanghai", "SHA": "Asia/Shanghai", "CAN": "Asia/Shanghai",
    "SIN": "Asia/Singapore", "BKK": "Asia/Bangkok", "DMK": "Asia/Bangkok", "SGN": "Asia/Ho_Chi_Minh", "HAN": "Asia/Bangkok",
    "MNL": "Asia/Manila", "KUL": "Asia/Kuala_Lumpur", "CGK": "Asia/Jakarta", "DPS": "Asia/Makassar",
    // Europe
    "LHR": "Europe/London", "LGW": "Europe/London", "CDG": "Europe/Paris", "ORY": "Europe/Paris", "NCE": "Europe/Paris",
    "FRA": "Europe/Berlin", "MUC": "Europe/Berlin", "BER": "Europe/Berlin", "AMS": "Europe/Amsterdam",
    "MAD": "Europe/Madrid", "BCN": "Europe/Madrid", "FCO": "Europe/Rome", "MXP": "Europe/Rome", "VCE": "Europe/Rome",
    "LIS": "Europe/Lisbon", "OPO": "Europe/Lisbon", "CPH": "Europe/Copenhagen", "ARN": "Europe/Stockholm",
    "OSL": "Europe/Oslo", "ZRH": "Europe/Zurich", "VIE": "Europe/Vienna", "IST": "Europe/Istanbul", "DUB": "Europe/Dublin",
    // North America
    "SFO": "America/Los_Angeles", "LAX": "America/Los_Angeles", "SEA": "America/Los_Angeles", "SAN": "America/Los_Angeles",
    "SJC": "America/Los_Angeles", "PDX": "America/Los_Angeles", "LAS": "America/Los_Angeles", "YVR": "America/Vancouver",
    "JFK": "America/New_York", "EWR": "America/New_York", "LGA": "America/New_York", "BOS": "America/New_York",
    "IAD": "America/New_York", "DCA": "America/New_York", "ATL": "America/New_York", "MIA": "America/New_York", "YYZ": "America/Toronto",
    "ORD": "America/Chicago", "DFW": "America/Chicago", "IAH": "America/Chicago", "DEN": "America/Denver", "PHX": "America/Phoenix",
    "HNL": "Pacific/Honolulu", "MEX": "America/Mexico_City", "CUN": "America/Cancun", "GRU": "America/Sao_Paulo",
    // Oceania · Middle East
    "SYD": "Australia/Sydney", "MEL": "Australia/Melbourne", "AKL": "Pacific/Auckland", "DXB": "Asia/Dubai", "DOH": "Asia/Qatar",
  ]

  /// Countries with one time zone (for hotels). Countries with several are left out on purpose.
  static let countries: [String: String] = [
    "JP": "Asia/Tokyo", "KR": "Asia/Seoul", "TW": "Asia/Taipei", "HK": "Asia/Hong_Kong", "CN": "Asia/Shanghai",
    "SG": "Asia/Singapore", "TH": "Asia/Bangkok", "VN": "Asia/Ho_Chi_Minh", "PH": "Asia/Manila", "MY": "Asia/Kuala_Lumpur",
    "GB": "Europe/London", "IE": "Europe/Dublin", "FR": "Europe/Paris", "DE": "Europe/Berlin", "NL": "Europe/Amsterdam",
    "BE": "Europe/Brussels", "IT": "Europe/Rome", "ES": "Europe/Madrid", "CH": "Europe/Zurich", "AT": "Europe/Vienna",
    "DK": "Europe/Copenhagen", "SE": "Europe/Stockholm", "NO": "Europe/Oslo", "FI": "Europe/Helsinki", "GR": "Europe/Athens",
    "CZ": "Europe/Prague", "PL": "Europe/Warsaw", "TR": "Europe/Istanbul", "AE": "Asia/Dubai", "QA": "Asia/Qatar", "NZ": "Pacific/Auckland",
  ]

  /// "San Francisco (SFO)" or "SFO" → "America/Los_Angeles".
  static func airport(_ place: String?) -> String? {
    guard let place else { return nil }
    if let r = place.range(of: #"\(([A-Z]{3})\)"#, options: .regularExpression) {
      return airports[String(place[r].dropFirst().dropLast())]
    }
    let t = place.trimmingCharacters(in: .whitespaces).uppercased()
    return t.count == 3 ? airports[t] : nil
  }

  static func country(_ code: String?) -> String? { code.flatMap { countries[$0.uppercased()] } }

  /// The real moment of a wall-clock time written in `zone`. `wall` was read in the phone's own
  /// time zone (how TripTimeline parses bookings), so its clock fields are re-read in `zone`.
  static func instant(_ wall: Date, in zone: String?) -> Date {
    guard let zone, let tz = TimeZone(identifier: zone), tz != .current else { return wall }
    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wall)
    var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
    return cal.date(from: comps) ?? wall
  }
}
