import PhotosUI
import SwiftData
import SwiftUI

/// Trip › Spend: what you've spent on the trip, in the local currency now and your own once
/// the live rate comes in (Figma: 07 · Spending Flow).
struct SpendContent: View {
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var net
  @Query(sort: \ExpenseItem.spentAt, order: .reverse) private var expenses: [ExpenseItem]
  @Query private var packs: [DestinationPack]
  let dayLine: String
  @State private var byCategory = 0
  @State private var editing: ExpenseItem?
  @State private var newExpense: ExpenseItem?
  @State private var photo: PhotosPickerItem?
  @State private var reading = false
  @State private var readError: String?
  @State private var showReport = false

  private var country: String? { packs.first?.countryCode }
  private var currency: String { Spend.currency(country: country) ?? expenses.first?.currency ?? Spend.homeCurrency }
  private var rate: FXRate? { ExpenseService.savedRate }
  private var home: String { Spend.homeCurrency }

  var body: some View {
    let total = Spend.localTotal(expenses)
    let homeTotal = Spend.homeTotal(expenses, rate: rate)
    let left = ExpenseService.budget - (homeTotal ?? 0)
    let status = Spend.status(spent: homeTotal ?? 0, budget: ExpenseService.budget)
    let today = expenses.filter { TripTimeline.calendar.isDate($0.spentAt, inSameDayAs: AppClock.now) }
    VStack(alignment: .leading, spacing: 14) {
      MTALabel("\(dayLine) · \(net.isOnline ? "online" : "offline")")
      VStack(alignment: .leading, spacing: 2) {
        Text(Spend.money(total, currency)).mta(.displayLarge).monospacedDigit().foregroundStyle(MTA.text)
          .lineLimit(1).minimumScaleFactor(0.6)
        Text(rateLine(homeTotal)).mta(.body2).foregroundStyle(MTA.text2)
      }
      HStack(spacing: 8) {
        NumberBox(value: Spend.money(Spend.localTotal(today), currency), caption: "Today", style: .filled)
        NumberBox(value: homeTotal == nil ? "—" : Spend.money(max(left, 0), home, whole: true), caption: "Budget left",
                  style: .status(status == .near ? .obstacle : .onTrack))
        NumberBox(value: "\(Spend.toSettle(expenses))", caption: "To settle",
                  style: Spend.toSettle(expenses) > 0 ? .tinted(.obstacle) : .outline)
      }
      if !expenses.isEmpty {
        MTASegmented(options: ["By day", "By category"], selection: $byCategory)
        if byCategory == 0 {
          ForEach(Spend.byDay(expenses), id: \.day) { group in
            MTALabel(dayTitle(group.day, group.items)).padding(.top, 4)
            ForEach(group.items) { e in row(e) }
          }
        } else {
          ForEach(Spend.byCategory(expenses), id: \.category) { group in
            MTALabel("\(group.category.title) · \(Spend.money(Spend.localTotal(group.items), currency))").padding(.top, 4)
            ForEach(group.items) { e in row(e) }
          }
        }
        Button { showReport = true } label: {
          HStack {
            Text("Trip report").mta(.subheadNormal).foregroundStyle(MTA.text)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(MTA.text2)
          }
          .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
      } else {
        Text("Scan receipts as you go. Your iPhone reads them, even with no signal.")
          .mta(.body1).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      }
      if let readError { NoticeCard(text: readError) }
      HStack(spacing: 10) {
        PhotosPicker(selection: $photo, matching: .images) {
          Label(reading ? "Reading…" : "Scan a receipt", systemImage: "doc.text.viewfinder")
        }
        .buttonStyle(.mtaPrimary).disabled(reading)
        Button("Add") { newExpense = ExpenseItem(spentAt: AppClock.now, merchant: "", amount: 0, currency: currency, category: .food) }
          .buttonStyle(.mtaSecondary).frame(width: 96)
      }
      .padding(.top, 6)
    }
    .onChange(of: photo) { _, item in if let item { Task { await scan(item) } } }
    .sheet(item: $editing) { ExpenseEditor(expense: $0, isNew: false) }
    .sheet(item: $newExpense) { ExpenseEditor(expense: $0, isNew: true, meta: lastMeta) }
    .navigationDestination(isPresented: $showReport) { SpendReport() }
    #if DEBUG
    .task {
      // `-scanSample`: read a sample receipt (the simulator has no camera).
      if ProcessInfo.processInfo.arguments.contains("-scanSample") { await read(lines: ExpenseService.sampleLines) }
      if ProcessInfo.processInfo.arguments.contains("-spendReport") { showReport = true }
    }
    #endif
  }

  @State private var lastMeta: AIMeta?

  private func rateLine(_ homeTotal: Double?) -> String {
    guard let homeTotal else { return "In \(home) once the live rate comes in" }
    if Spend.toSettle(expenses) == 0, !expenses.isEmpty { return "≈ \(Spend.money(homeTotal, home)) · settled at the live rate" }
    let day = rate.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
    return "≈ \(Spend.money(homeTotal, home, whole: true)) at the \(day) rate · updates when you’re online"
  }

  private func dayTitle(_ day: Date, _ items: [ExpenseItem]) -> String {
    let cal = TripTimeline.calendar
    let name = cal.isDate(day, inSameDayAs: AppClock.now) ? "Today · " : ""
    return "\(name)\(TripTimeline.dayTitle(day)) · \(Spend.money(Spend.localTotal(items), currency))"
  }

  private func row(_ e: ExpenseItem) -> some View {
    Button { editing = e } label: {
      HStack(spacing: 12) {
        TripIcon(symbol: e.kind.symbol, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(e.merchant).mta(.subheadNormal).foregroundStyle(MTA.text).lineLimit(1)
          HStack(spacing: 6) {
            Text([e.kind.title, TripTimeline.time(e.spentAt), e.paidWith?.lowercased()].compactMap { $0 }.joined(separator: " · "))
              .mta(.body2).foregroundStyle(MTA.text2).lineLimit(1)
            if !e.settled && rate == nil { Chip(text: "Offline", color: MTA.obstacle) }
          }
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 2) {
          Text(Spend.money(e.amount, e.currency)).mta(.subheadNormal).monospacedDigit().foregroundStyle(MTA.text)
          if let h = Spend.home(e, rate: rate) {
            Text("≈ " + Spend.money(h, home)).mta(.body2).monospacedDigit().foregroundStyle(MTA.text2)
          } else {
            Text("rate pending").mta(.body2).foregroundStyle(MTA.obstacle)
          }
        }
      }
      .padding(.vertical, 10)
      .overlay(alignment: .bottom) { Rectangle().fill(MTA.subtle.opacity(0.5)).frame(height: 1) }
    }
    .buttonStyle(.plain)
  }

  private func scan(_ item: PhotosPickerItem) async {
    defer { photo = nil }
    guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data), let cg = ui.cgImage else {
      readError = "I couldn't open that photo."; return
    }
    let start = ContinuousClock.now
    let lines = ExpenseService.lines(in: cg)
    ai.logOnDevice("Spend · read a photo", .survive, reason: "Apple Vision on this iPhone · the photo stays here",
                   latencyMs: (ContinuousClock.now - start).milliseconds, note: "\(lines.count) lines of text")
    await read(lines: lines)
  }

  private func read(lines: [String]) async {
    guard !lines.isEmpty else { readError = "I couldn't find any text. Try a photo with the whole receipt."; return }
    reading = true; readError = nil
    defer { reading = false }
    do {
      let (e, meta) = try await ExpenseService.read(lines: lines, country: country, ai: ai)
      lastMeta = meta
      newExpense = e
    } catch {
      // Nothing read: open an empty expense with the total code found, so nothing is lost.
      newExpense = ExpenseItem(spentAt: AppClock.now, merchant: lines.first ?? "", amount: ReceiptTotal.find(lines) ?? 0,
                               currency: currency, category: .other, source: "scan")
      readError = "I couldn't read it all. Check the amount and save."
    }
  }
}

// MARK: - New / edit expense

struct ExpenseEditor: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Bindable var expense: ExpenseItem
  let isNew: Bool
  var meta: AIMeta?
  @State private var amountText = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let meta, expense.source == "scan" {
            MTALabel("\(meta.source == .onDevice ? "On-device" : "Cloud · Gemini") · \(SourceChip.format(meta.latencyMs)) · from your photo",
                     color: meta.source == .onDevice ? MTA.onTrack : MTA.accent)
          }
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbol).mta(.displayMedium).foregroundStyle(MTA.text2)
            TextField("0", text: $amountText).keyboardType(.decimalPad).mta(.displayLarge).monospacedDigit()
              .onChange(of: amountText) { _, t in expense.amount = Double(t.replacingOccurrences(of: ",", with: "")) ?? 0 }
          }
          if let r = ExpenseService.savedRate, r.local == expense.currency {
            Text("≈ \(Spend.money(expense.amount / r.localPerHome, r.home)) at the \(r.date.formatted(.dateTime.month(.abbreviated).day())) rate")
              .mta(.body2).foregroundStyle(MTA.text2)
          }
          VStack(spacing: 0) {
            field("Place") { TextField("Shop or restaurant", text: $expense.merchant).multilineTextAlignment(.trailing) }
            if let local = expense.merchantLocal { field("On receipt") { Text(local).foregroundStyle(MTA.text) } }
            field("When") { DatePicker("", selection: $expense.spentAt).labelsHidden() }
            field("Paid with") {
              Picker("", selection: Binding(get: { expense.paidWith ?? "Cash" }, set: { expense.paidWith = $0 })) {
                ForEach(["Cash", "Card", "IC card"], id: \.self) { Text($0) }
              }.pickerStyle(.menu).labelsHidden()
            }
            field("Currency", last: true) { Text(expense.currency).foregroundStyle(MTA.text) }
          }
          .padding(.horizontal, 14)
          .background(MTA.raised, in: .rect(cornerRadius: 16))
          MTALabel("Category")
          FlowChips(selected: expense.kind) { expense.category = $0.rawValue }
          if !expense.lines.isEmpty {
            MTALabel("Items · translated on this iPhone")
            ForEach(expense.lines, id: \.self) { l in
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                  Text(l.english).mta(.button2).foregroundStyle(MTA.text)
                  Text(l.name).mta(.body2).foregroundStyle(MTA.text2)
                }
                Spacer()
                Text(Spend.money(l.price, expense.currency)).mta(.button2).monospacedDigit().foregroundStyle(MTA.text)
              }
            }
          }
          Button(isNew ? "Save expense" : "Done") { save() }
            .buttonStyle(.mtaPrimary).disabled(expense.amount <= 0 || expense.merchant.isEmpty).padding(.top, 8)
          Text("The photo stays on this iPhone. Card numbers are never read.")
            .mta(.body2).foregroundStyle(MTA.text2).frame(maxWidth: .infinity)
          if !isNew {
            Button("Delete", role: .destructive) { context.delete(expense); try? context.save(); dismiss() }
              .frame(maxWidth: .infinity)
          }
        }
        .mtaScreen().padding(.vertical, 12)
      }
      .background(MTA.surface)
      .navigationTitle(isNew ? "New expense" : "Expense")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(isNew ? "Cancel" : "Close") { dismiss() } } }
      .onAppear {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        amountText = expense.amount > 0 ? (f.string(from: NSNumber(value: expense.amount)) ?? "") : ""
      }
    }
  }

  private var symbol: String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = expense.currency
    f.locale = Locale(identifier: expense.currency == "JPY" ? "ja_JP" : "en_US")
    return f.currencySymbol ?? expense.currency
  }

  private func field<V: View>(_ label: String, last: Bool = false, @ViewBuilder _ value: () -> V) -> some View {
    HStack { Text(label).mta(.body2).foregroundStyle(MTA.text2); Spacer(); value().mta(.button2) }
      .padding(.vertical, 12)
      .overlay(alignment: .bottom) { if !last { Rectangle().fill(MTA.subtle.opacity(0.5)).frame(height: 1) } }
  }

  private func save() {
    if isNew { context.insert(expense) }
    try? context.save()
    dismiss()
  }
}

/// Category chips; the selected one is filled.
struct FlowChips: View {
  let selected: ExpenseCategory
  var pick: (ExpenseCategory) -> Void
  var body: some View {
    let rows = [Array(ExpenseCategory.allCases.prefix(3)), Array(ExpenseCategory.allCases.suffix(3))]
    VStack(alignment: .leading, spacing: 8) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: 8) {
          ForEach(row, id: \.self) { c in
            Button { pick(c) } label: {
              Text(c.title).mta(.button2)
                .foregroundStyle(c == selected ? MTA.textInverse : MTA.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background { if c == selected { Capsule().fill(MTA.inverse) } else { Capsule().strokeBorder(MTA.border, lineWidth: 2) } }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

// MARK: - Trip report

struct SpendReport: View {
  @Query(sort: \ExpenseItem.spentAt) private var expenses: [ExpenseItem]
  @Query private var packs: [DestinationPack]
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @Query(sort: \TripPlan.start) private var plans: [TripPlan]

  private var home: String { Spend.homeCurrency }
  private var currency: String { Spend.currency(country: packs.first?.countryCode) ?? expenses.first?.currency ?? home }

  var body: some View {
    let rate = ExpenseService.savedRate
    let total = Spend.homeTotal(expenses, rate: rate)
    let settledAll = Spend.toSettle(expenses) == 0 && !expenses.isEmpty
    let budget = ExpenseService.budget
    let status = Spend.status(spent: total ?? 0, budget: budget)
    let range = TripTimeline.range(TripTimeline.events(items: items, plans: plans))
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if ExpenseService.lastSettled > 0, let r = rate {
          HStack(spacing: 10) {
            Circle().fill(MTA.onTrack).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
              Text("Settled \(ExpenseService.lastSettled) expense\(ExpenseService.lastSettled == 1 ? "" : "s")").mta(.button2)
              Text("Back online · live rate \(Spend.money(r.localPerHome, r.local)) = \(Spend.money(1, r.home))").mta(.body2).opacity(0.8)
            }
            Spacer()
          }
          .foregroundStyle(MTA.textInverse)
          .padding(14).background(MTA.inverse, in: .rect(cornerRadius: 20))
        }
        MTALabel([packs.first?.countryName, range.map { "\($0.lowerBound.formatted(.dateTime.month(.abbreviated).day())) – \($0.upperBound.formatted(.dateTime.month(.abbreviated).day()))" },
                  settledAll ? "settled" : "\(Spend.toSettle(expenses)) to settle"].compactMap { $0 }.joined(separator: " · "))
        Text(total.map { Spend.money($0, home) } ?? Spend.money(Spend.localTotal(expenses), currency))
          .mta(.displayLarge).monospacedDigit().foregroundStyle(MTA.text)
        Text("\(Spend.money(Spend.localTotal(expenses), currency)) · \(status == .near ? "near" : "within") your \(Spend.money(budget, home)) budget")
          .mta(.body2).foregroundStyle(MTA.text2)
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(MTA.raised)
            Capsule().fill(status == .near ? MTA.obstacle : MTA.onTrack).frame(width: g.size.width * min(1, (total ?? 0) / max(budget, 1)))
          }
        }
        .frame(height: 12)
        MTALabel("By category").padding(.top, 6)
        VStack(spacing: 0) {
          tableRow(["Category", currency, home], header: true)
          ForEach(Spend.byCategory(expenses), id: \.category) { g in
            tableRow([g.category.title, Spend.money(Spend.localTotal(g.items), currency),
                      Spend.homeTotal(g.items, rate: rate).map { Spend.money($0, home) } ?? "—"])
          }
          tableRow(["Total", Spend.money(Spend.localTotal(expenses), currency), total.map { Spend.money($0, home) } ?? "—"], total: true)
        }
        Text("Hotel and flights paid before the trip aren’t counted here.").mta(.body2).foregroundStyle(MTA.text2)
        ShareLink(item: Spend.csv(expenses, home: home), preview: SharePreview("Trip spending.csv")) {
          Label("Export CSV", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.mtaSecondary).padding(.top, 8)
      }
      .mtaScreen().padding(.vertical, 12)
    }
    .background(MTA.surface)
    .navigationTitle("Trip report")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func tableRow(_ cells: [String], header: Bool = false, total: Bool = false) -> some View {
    HStack {
      Text(cells[0]).frame(maxWidth: .infinity, alignment: .leading)
      Text(cells[1]).frame(width: 96, alignment: .trailing)
      Text(cells[2]).frame(width: 96, alignment: .trailing)
    }
    .font(header ? MTAType.label.font : (total ? MTAType.button2.font : MTAType.body1.font))
    .textCase(header ? .uppercase : nil)
    .monospacedDigit()
    .foregroundStyle(header ? MTA.text2 : MTA.text)
    .padding(.vertical, 11)
    .overlay(alignment: .top) { if !header { Rectangle().fill(total ? MTA.border : MTA.subtle.opacity(0.5)).frame(height: total ? 2 : 1) } }
  }
}
