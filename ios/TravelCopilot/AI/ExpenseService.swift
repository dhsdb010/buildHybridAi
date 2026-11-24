import CoreGraphics
import Foundation
import FoundationModels
import SwiftData

@Generable
struct ReceiptRead {
  @Guide(description: "The shop or restaurant name exactly as printed on the receipt")
  var merchantLocal: String
  @Guide(description: "The shop name in English letters (romanized or translated), short")
  var merchant: String
  @Guide(description: "The total paid, as a number with no currency sign")
  var total: Double
  @Guide(description: "ISO currency code, e.g. JPY, KRW, EUR")
  var currency: String
  @Guide(description: "One of: food, transport, shopping, sights, stay, other")
  var category: String
  @Guide(description: "How it was paid if printed: Cash, Card or IC card. Empty if not printed.")
  var paidWith: String
  @Guide(description: "Each item line: the name as printed, an English translation, and its price", .maximumCount(8))
  var items: [ReceiptItem]
}

@Generable
struct ReceiptItem {
  var name: String
  var english: String
  var price: Double
}

/// Spending: reading receipts on this iPhone, and settling amounts at the live exchange rate.
/// Reading runs on the device first (works offline); the exchange rate needs the network, so
/// amounts made offline are settled by the catch-up pass when the connection is back.
@MainActor
enum ExpenseService {
  // MARK: Exchange rate

  private static let rateKey = "fxRate"

  /// The last rate saved on this iPhone (from Prepare or a catch-up pass).
  static var savedRate: FXRate? {
    get { UserDefaults.standard.data(forKey: rateKey).flatMap { try? JSONDecoder().decode(FXRate.self, from: $0) } }
    set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: rateKey) }
  }

  /// Budget for the trip in the home currency (Spend › Budget). Default 1,000.
  static var budget: Double {
    get { (UserDefaults.standard.object(forKey: "spendBudget") as? Double) ?? 1000 }
    set { UserDefaults.standard.set(newValue, forKey: "spendBudget") }
  }

  nonisolated struct RateReply: Decodable { let date: String; let rates: [String: Double] }

  /// Today's rate from the European Central Bank reference rates (Frankfurter, no key, no
  /// personal data: only the two currency codes are sent).
  static func fetchRate(local: String, home: String) async throws -> FXRate {
    var c = URLComponents(string: "https://api.frankfurter.app/latest")!
    c.queryItems = [.init(name: "from", value: home), .init(name: "to", value: local)]
    let (data, response) = try await URLSession.shared.data(from: c.url!)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try parse(data, local: local, home: home)
  }

  nonisolated static func parse(_ data: Data, local: String, home: String) throws -> FXRate {
    let reply = try JSONDecoder().decode(RateReply.self, from: data)
    guard let r = reply.rates[local], r > 0 else { throw URLError(.cannotParseResponse) }
    // The rate's day, as a local date ("2026-11-28" stays Nov 28 in every time zone).
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
    return FXRate(local: local, home: home, localPerHome: r, date: f.date(from: reply.date + " 12:00") ?? Date())
  }

  /// Saves today's rate while you're on Wi-Fi (Prepare), so amounts show in your currency offline.
  static func refreshRate(country: String?) async {
    guard let local = Spend.currency(country: country) else { return }
    let home = Spend.homeCurrency
    guard local != home else { return }
    if let r = try? await fetchRate(local: local, home: home) { savedRate = r }
  }

  /// Catch-up: converts every unsettled expense at today's live rate. Logged like any other step.
  @discardableResult
  static func settle(ai: AIService) async -> Int {
    let open = ((try? ai.context.fetch(FetchDescriptor<ExpenseItem>())) ?? []).filter { !$0.settled }
    guard !open.isEmpty else { return 0 }
    guard case .run = RoutingPolicy.decide(.catchUp, ai.routingContext) else { return 0 }
    let home = Spend.homeCurrency
    var settled = 0
    var rates: [String: FXRate] = [:]
    for e in open {
      if e.currency == home { e.homeAmount = e.amount; e.rate = 1; e.rateDate = Date(); e.settled = true; settled += 1; continue }
      if rates[e.currency] == nil { rates[e.currency] = try? await fetchRate(local: e.currency, home: home) }
      guard let r = rates[e.currency] else { continue }
      e.homeAmount = (e.amount / r.localPerHome * 100).rounded() / 100
      e.rate = r.localPerHome
      e.rateDate = r.date
      e.settled = true
      settled += 1
    }
    if let r = rates.values.first { savedRate = r }
    try? ai.context.save()
    if settled > 0 {
      let rateText = rates.values.first.map { "live rate \(Spend.money($0.localPerHome, $0.local)) = \(Spend.money(1, home))" } ?? ""
      ai.note("Spend · settle", .catchUp, reason: "Back online", outcome: "ok",
              note: "Settled \(settled) expense\(settled == 1 ? "" : "s")" + (rateText.isEmpty ? "" : " · \(rateText)"))
    }
    lastSettled = settled
    return settled
  }

  /// How many expenses the last catch-up pass settled (Spend shows a one-time message).
  static var lastSettled = 0

  // MARK: Receipt

  static let instructions = """
    You read a shop or restaurant receipt from text recognized in a photo. Use only what the text says.
    Never invent items or amounts. The total is the amount on the total line (合計, Total, 합계).
    """

  /// Reads a receipt from the recognized text lines. Runs on this iPhone first (works offline);
  /// code checks the total against the text.
  static func read(lines: [String], country: String?, ai: AIService) async throws -> (ExpenseItem, AIMeta) {
    let text = lines.joined(separator: "\n")
    let (r, meta) = try await ai.generate("Spend · read a receipt", kind: .survive,
                                          prompt: "Receipt text:\n\(text.prefix(1500))", instructions: instructions, as: ReceiptRead.self)
    // Code, not AI, decides the total: if the model's number isn't on the total line, use the one that is.
    let found = ReceiptTotal.find(lines)
    let total = (found != nil && abs((found ?? 0) - r.total) > 0.5) ? found! : r.total
    let currency = (r.currency.count == 3 ? r.currency.uppercased() : nil) ?? Spend.currency(country: country) ?? Spend.homeCurrency
    let paid = ["cash", "card", "ic card"].first { r.paidWith.lowercased().contains($0) }.map { $0 == "ic card" ? "IC card" : $0.capitalized }
    let item = ExpenseItem(spentAt: AppClock.now, merchant: r.merchant.isEmpty ? r.merchantLocal : r.merchant,
                           merchantLocal: r.merchantLocal.isEmpty ? nil : r.merchantLocal, amount: total, currency: currency,
                           category: ExpenseCategory.from(r.category), paidWith: paid,
                           lines: r.items.map { ExpenseLine(name: $0.name, english: $0.english, price: $0.price) }, source: "scan")
    return (item, meta)
  }

  /// Text in the receipt photo, read with Vision on this iPhone. The photo isn't saved.
  static func lines(in image: CGImage) -> [String] { TextInImage.read(image) }

  #if DEBUG
    /// `-scanSample`: a sample receipt's recognized text, for the simulator (it has no camera).
    nonisolated static let sampleLines = ["一蘭 新宿中央東口店", "2026/12/03 12:40", "天然とんこつラーメン ¥980", "替玉 ¥200",
                              "合計 ¥1,180", "お預り (現金) ¥2,000", "お釣り ¥820"]
  #endif
}
