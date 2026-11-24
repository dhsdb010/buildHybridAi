import Foundation
import SwiftData

/// One thing the traveler paid for on the trip. Saved on the phone; the amount is in the
/// local currency. `homeAmount` is filled in by the catch-up pass at the live rate.
@Model
final class ExpenseItem {
  var spentAt: Date
  /// Readable name ("Ichiran Shinjuku").
  var merchant: String
  /// As printed on the receipt ("一蘭 新宿中央東口店").
  var merchantLocal: String?
  /// In `currency`.
  var amount: Double
  /// ISO code, e.g. "JPY".
  var currency: String
  /// `ExpenseCategory` raw value.
  var category: String
  /// "Cash", "Card", "IC card".
  var paidWith: String?
  var lines: [ExpenseLine] = []
  /// Settled amount in the home currency (after the catch-up pass).
  var homeAmount: Double?
  /// Units of `currency` per one home unit at settlement (¥149.6 = $1 → 149.6).
  var rate: Double?
  var rateDate: Date?
  var settled: Bool = false
  /// "scan" (read from a receipt photo on this iPhone) or "manual".
  var source: String = "manual"
  var createdAt: Date = Date()

  init(spentAt: Date, merchant: String, merchantLocal: String? = nil, amount: Double, currency: String,
       category: ExpenseCategory, paidWith: String? = nil, lines: [ExpenseLine] = [], source: String = "manual") {
    self.spentAt = spentAt
    self.merchant = merchant
    self.merchantLocal = merchantLocal
    self.amount = amount
    self.currency = currency
    self.category = category.rawValue
    self.paidWith = paidWith
    self.lines = lines
    self.source = source
  }

  var kind: ExpenseCategory { ExpenseCategory(rawValue: category) ?? .other }
}

/// A line on a receipt, translated on this iPhone ("替玉" → "Extra noodles").
struct ExpenseLine: Codable, Hashable, Sendable {
  var name: String
  var english: String
  var price: Double
}

enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
  case food, transport, shopping, sights, stay, other

  var title: String { rawValue.capitalized }
  var symbol: String {
    switch self {
    case .food: "fork.knife"
    case .transport: "tram"
    case .shopping: "bag"
    case .sights: "building.columns"
    case .stay: "bed.double"
    case .other: "ellipsis"
    }
  }

  /// "Food", "food & drink", "restaurant" → .food. Anything unknown → .other.
  static func from(_ s: String) -> ExpenseCategory {
    let t = s.lowercased()
    if let c = ExpenseCategory(rawValue: t) { return c }
    if ["restaurant", "cafe", "café", "drink", "meal", "grocery", "convenience"].contains(where: t.contains) { return .food }
    if ["train", "subway", "bus", "taxi", "metro", "transit"].contains(where: t.contains) { return .transport }
    if ["shop", "store", "souvenir"].contains(where: t.contains) { return .shopping }
    if ["museum", "temple", "ticket", "admission", "tour"].contains(where: t.contains) { return .sights }
    if ["hotel", "hostel", "lodging"].contains(where: t.contains) { return .stay }
    return .other
  }
}

/// A saved exchange rate: `localPerHome` units of `local` buy one unit of `home`.
struct FXRate: Codable, Equatable, Sendable {
  var local: String
  var home: String
  var localPerHome: Double
  var date: Date
}

/// Spending math, kept apart from the views so it can be tested.
enum Spend {
  /// Budget status: green while under 80% of the budget, orange from 80% (and over).
  enum Status: Equatable { case onTrack, near }
  static let nearShare = 0.8

  static func status(spent: Double, budget: Double) -> Status {
    guard budget > 0 else { return .onTrack }
    return spent >= budget * nearShare ? .near : .onTrack
  }

  /// The trip's currency, from the country ("JP" → "JPY").
  static func currency(country: String?) -> String? {
    guard let country, !country.isEmpty else { return nil }
    return Locale(identifier: "und_\(country)").currency?.identifier
  }

  /// The traveler's home currency, from the iPhone's region.
  static var homeCurrency: String { Locale.current.currency?.identifier ?? "USD" }

  /// Home-currency value: the settled amount, else today's estimate at `rate`.
  static func home(_ e: ExpenseItem, rate: FXRate?) -> Double? {
    if let h = e.homeAmount { return h }
    guard let rate, rate.local == e.currency, rate.localPerHome > 0 else { return nil }
    return e.amount / rate.localPerHome
  }

  static func localTotal(_ items: [ExpenseItem]) -> Double { items.reduce(0) { $0 + $1.amount } }

  static func homeTotal(_ items: [ExpenseItem], rate: FXRate?) -> Double? {
    var sum = 0.0
    for e in items { guard let h = home(e, rate: rate) else { return nil }; sum += h }
    return sum
  }

  static func toSettle(_ items: [ExpenseItem]) -> Int { items.filter { !$0.settled }.count }

  /// Newest day first; each day's expenses newest first.
  static func byDay(_ items: [ExpenseItem]) -> [(day: Date, items: [ExpenseItem])] {
    let cal = TripTimeline.calendar
    let groups = Dictionary(grouping: items) { cal.startOfDay(for: $0.spentAt) }
    return groups.keys.sorted(by: >).map { d in (d, groups[d]!.sorted { $0.spentAt > $1.spentAt }) }
  }

  /// Biggest category first.
  static func byCategory(_ items: [ExpenseItem]) -> [(category: ExpenseCategory, items: [ExpenseItem])] {
    let groups = Dictionary(grouping: items) { $0.kind }
    return groups.map { ($0.key, $0.value) }.sorted { localTotal($0.1) > localTotal($1.1) }
  }

  /// "¥18,420" · "$123.13" (no decimals for currencies that don't use them).
  static func money(_ value: Double, _ code: String, whole: Bool = false) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    if whole { f.maximumFractionDigits = 0 }
    f.locale = Locale(identifier: code == "JPY" ? "ja_JP" : code == "KRW" ? "ko_KR" : "en_US")
    if code == "USD" { f.currencySymbol = "$" }
    return f.string(from: NSNumber(value: value)) ?? "\(code) \(value)"
  }

  /// A CSV of every expense, for Export.
  static func csv(_ items: [ExpenseItem], home: String) -> String {
    let day = Date.ISO8601FormatStyle().year().month().day()
    var rows = ["date,place,category,amount,currency,\(home.lowercased()),settled"]
    for e in items.sorted(by: { $0.spentAt < $1.spentAt }) {
      let place = e.merchant.replacingOccurrences(of: "\"", with: "'")
      let h = e.homeAmount.map { String(format: "%.2f", $0) } ?? ""
      rows.append("\(e.spentAt.formatted(day)),\"\(place)\",\(e.category),\(e.amount),\(e.currency),\(h),\(e.settled)")
    }
    return rows.joined(separator: "\n")
  }
}

/// The receipt's total, found by code (not AI): the number on the "total" line, else the biggest
/// amount. Used to check what the model read, so a wrong total is never saved silently.
enum ReceiptTotal {
  static let keywords = ["合計", "合　計", "総計", "お会計", "total", "합계", "总计", "總計", "montant", "summe", "totale"]

  static func amounts(in line: String) -> [Double] {
    let pattern = #"(?<![\d.])\d{1,3}(?:[,，]\d{3})+(?:\.\d{1,2})?(?!\d)|(?<![\d.,])\d+(?:\.\d{1,2})?(?![\d,])"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = line as NSString
    return re.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
      Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: ""))
    }
  }

  static func find(_ lines: [String]) -> Double? {
    for (i, line) in lines.enumerated() where keywords.contains(where: { line.lowercased().contains($0) }) {
      if let v = amounts(in: line).last { return v }
      if i + 1 < lines.count, let v = amounts(in: lines[i + 1]).first { return v }
    }
    return nil
  }
}
