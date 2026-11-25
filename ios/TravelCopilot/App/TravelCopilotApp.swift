import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck
import GoogleSignIn
import UserNotifications

/// App Check provider for release builds (needs the App Attest capability, set in project.yml).
final class AppAttestFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? { AppAttestProvider(app: app) }
}

@main
struct TravelCopilotApp: App {
  /// False when GoogleService-Info.plist hasn't been added yet (see SETUP.md).
  static let firebaseConfigured: Bool = {
    guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
      return false
    }
    #if DEBUG
      // Prints "App Check debug token: ..." to the Xcode console on first launch.
      // Register it in Firebase console > App Check > Apps > Manage debug tokens.
      AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    #else
      // TestFlight and App Store: Apple's App Attest proves requests come from this app.
      AppCheck.setAppCheckProviderFactory(AppAttestFactory())
    #endif
    FirebaseApp.configure()
    return true
  }()

  let container: ModelContainer
  @State private var connectivity: Connectivity
  @State private var ai: AIService
  @State private var router = AppRouter()
  @State private var location = LocationService()
  @State private var auth = AuthService()
  @State private var social = SocialService.live()
  private let notifications = NotificationActions()

  init() {
    _ = Self.firebaseConfigured
    let container = try! ModelContainer(for: VaultItem.self, DestinationPack.self, RoutingEntry.self, TranslationEntry.self, TripPlan.self, Place.self, MapPack.self, ChatMessage.self, RoutingSummary.self, EmergencyCard.self, ExpenseItem.self)
    let connectivity = Connectivity()
    self.container = container
    IDRepair.run(container.mainContext)
    RoutingLog.compact(container.mainContext)
    #if DEBUG
      // `-logKeep 10`: compact all but the latest 10 rows now (to see the Log's "Earlier" section).
      let keep = UserDefaults.standard.integer(forKey: "logKeep")
      if keep > 0 { RoutingLog.compact(container.mainContext, keep: keep) }
      // `-seedSpend`: sample expenses for the Spend screens (simulator screenshots).
      if ProcessInfo.processInfo.arguments.contains("-seedSpend") { SpendSample.seed(container.mainContext) }
      // `-seedTrip`: day-plan stops with places, for the trip summary map.
      if ProcessInfo.processInfo.arguments.contains("-seedTrip") { SpendSample.seedPlans(container.mainContext) }
    #endif
    _connectivity = State(initialValue: connectivity)
    _ai = State(initialValue: AIService(connectivity: connectivity, context: container.mainContext))
    // Done on the Live Activity / a notification → next step of the journey.
    JourneyIntentHandler.done = { await TripReminders.markDone($0) }
    // If the app was woken just for Done (not running before), rebuild the trip from storage.
    let context = container.mainContext
    TripReminders.reload = {
      let items = (try? context.fetch(FetchDescriptor<VaultItem>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
      let plans = (try? context.fetch(FetchDescriptor<TripPlan>())) ?? []
      let place = (try? context.fetch(FetchDescriptor<DestinationPack>()))?.first?.countryName ?? "Trip"
      let enabled = UserDefaults.standard.object(forKey: "planReminders") as? Bool ?? true
      return (TripTimeline.events(items: items, plans: plans), place, enabled)
    }
    UNUserNotificationCenter.current().delegate = notifications
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(connectivity)
        .environment(ai)
        .environment(router)
        .environment(location)
        .environment(auth)
        .environment(social)
        .onOpenURL { url in if !router.open(url) { GIDSignIn.sharedInstance.handle(url) } }
        // Friends and trip rooms follow the signed-in account.
        .onChange(of: auth.account?.uid, initial: true) { _, uid in
          if let uid, !uid.isEmpty {
            social.start(uid: uid, name: Profile.firstName(account: auth.account?.name) ?? auth.account?.name ?? "")
          } else if !social.isDemo { social.stop() }
        }
        .onAppear {
          notifications.router = router
          // Siri, the Action Button and the Control Center control open the emergency card.
          let router = router
          EmergencyIntentHandler.show = { router.emergency = .card }
        }
    }
    .modelContainer(container)
  }
}

enum AppTab: Hashable { case home, trip, map, prepare, log }

struct InviteRequest: Identifiable { let code: String; var id: String { code } }

struct AskRequest: Identifiable {
  let id = UUID()
  var mode: Int = 0        // 0 = Ask my trip, 1 = Say in <language>
  var text: String = ""
  var autoSubmit = false
}

/// App-wide navigation state: selected tab and the sheets any screen can open.
@MainActor
@Observable
final class AppRouter {
  var tab: AppTab = .home
  var ask: AskRequest?
  var showHelp = false
  var showSettings = false
  var showChats = false
  /// Opens the taxi card on Home (from a Live Activity or notification button).
  var showTaxi = false
  /// Opens Trip on a view: 0 List · 1 Spend · 2 Calendar (Home's Spend card).
  var tripMode: Int?
  /// The emergency card or its setup quiz, over everything (travelcopilot://emergency, Siri, debug).
  var emergency: EmergencyScreen?
  /// A friend's invite code from a link or QR (travelcopilot://i/CODE or https://…/i/CODE).
  var inviteCode: InviteRequest?

  /// travelcopilot://ask?q=… · ://trip · ://taxi · ://map · ://home. Returns false for other URLs.
  @discardableResult
  func open(_ url: URL) -> Bool {
    if (url.scheme == "https" || url.host() == "i"), let code = InviteCode.parse(url.absoluteString) {
      tab = .home; showChats = true; inviteCode = InviteRequest(code: code); return true
    }
    guard url.scheme == "travelcopilot" else { return false }
    switch url.host() {
    case "ask":
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
      ask = AskRequest(mode: 0, text: q, autoSubmit: false)
    case "trip": tab = .trip
    case "map": tab = .map
    case "taxi": tab = .home; showTaxi = true
    case "emergency": emergency = .card
    default: tab = .home
    }
    return true
  }

  init() {
    #if DEBUG
      // Debug launch arguments for simulator checks (see SETUP.md).
      let d = UserDefaults.standard
      switch d.string(forKey: "tab") { case "trip": tab = .trip; case "map": tab = .map; case "prepare": tab = .prepare; case "log": tab = .log; default: break }
      if let q = d.string(forKey: "askQuestion") { ask = AskRequest(mode: 0, text: q, autoSubmit: true) }
      if let q = d.string(forKey: "sayText") { ask = AskRequest(mode: 1, text: q, autoSubmit: true) }
      switch d.string(forKey: "screen") { case "help": showHelp = true; case "settings": showSettings = true; case "chats": showChats = true; case "ask": ask = AskRequest(); default: break }
      // `-emergency setup|card|english`: open the emergency card flow (simulator checks).
      if let e = d.string(forKey: "emergency") { emergency = EmergencyScreen(rawValue: e) }
    #endif
  }
}

struct RootView: View {
  @Environment(AppRouter.self) private var router
  @AppStorage("appearance") private var appearance = 0   // 0 system · 1 day · 2 night
  @AppStorage("onboarded") private var onboarded = false
  @AppStorage("planReminders") private var reminders = true
  @Environment(\.scenePhase) private var scenePhase
  @Environment(AIService.self) private var ai
  @Environment(Connectivity.self) private var connectivity
  @Query private var items: [VaultItem]
  @Query private var plans: [TripPlan]
  @Query private var packs: [DestinationPack]
  @State private var showWelcome = false

  var body: some View {
    @Bindable var router = router
    TabView(selection: $router.tab) {
      Tab("Home", systemImage: "house", value: AppTab.home) { HomeView() }
      Tab("Trip", systemImage: "suitcase.rolling", value: AppTab.trip) { TripView() }
      Tab("Map", systemImage: "map", value: AppTab.map) { MapScreen() }
      Tab("Prepare", systemImage: "square.and.arrow.down", value: AppTab.prepare) { PrepareView() }
      Tab("Log", systemImage: "list.bullet", value: AppTab.log) { RoutingLogView() }
    }
    .tint(MTA.accent)
    .overlay(alignment: .top) { CatchUpToast().padding(.top, 4) }
    .sheet(item: $router.ask) { AskView(request: $0) }
    .sheet(isPresented: $router.showHelp) { HelpView() }
    .fullScreenCover(item: $router.emergency) { EmergencyHost(screen: $0) }
    .fullScreenCover(isPresented: $showWelcome) { WelcomeView() }
    .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
    // Notifications + Live Activity for the next trip moment, refreshed when anything changes.
    .task(id: "\(items.count)-\(plans.count)-\(plans.map(\.start).hashValue)-\(reminders)-\(scenePhase == .active)") {
      // Not under unit tests (the permission prompt would block the test host).
      guard scenePhase == .active, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
      #if DEBUG
        // `-liveDemo`: a sample journey to the hotel (train → bus → walk → check-in) to see the Live Activity.
        // `-liveDemoStep far|train|bus|walk|arriving|arrived` picks where you are along it.
        if ProcessInfo.processInfo.arguments.contains("-liveDemo") {
          let step = UserDefaults.standard.string(forKey: "liveDemoStep") ?? "train"
          let shift: Double = switch step {
          case "far": -16 * 1440
          case "bus": 35
          case "walk": 58
          case "arriving": 68
          case "arrived": 110
          default: 0
          }
          // Earlier steps count as done (as if you'd tapped Done on each).
          let order = ["demo-train", "demo-bus", "demo-walk"]
          let doneCount = ["bus": 1, "walk": 2, "arriving": 3][step] ?? 0
          UserDefaults.standard.set(Array(order.prefix(doneCount)), forKey: "journeyDone")
          TripReminders.ignoreWindow = step == "far"
          let t0 = Date().addingTimeInterval(-shift * 60)
          func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
          let demo = [
            TripEvent(id: "demo-land", date: at(-40), kind: .arrive, title: "Land at Narita", detail: "TG 642",
                      itemID: nil, planSource: nil, vehicle: "flight"),
            TripEvent(id: "demo-train", date: at(18), kind: .depart, title: "Narita → Shinjuku",
                      detail: "Narita Express · Platform 1 · Car 8", itemID: nil, planSource: nil, vehicle: "train"),
            TripEvent(id: "demo-bus", date: at(42), kind: .plan, title: "Bus 61 → Nishi-Shinjuku",
                      detail: "Stop B4 · 3 min from the station", itemID: nil, planSource: "user"),
            TripEvent(id: "demo-walk", date: at(64), kind: .plan, title: "Walk to the hotel",
                      detail: "4 min walk", itemID: nil, planSource: "user"),
            TripEvent(id: "demo-in", date: at(72), kind: .checkIn, title: "Check in · Hotel Hoshizora Shinjuku",
                      detail: "Ref HSZ-48213", itemID: PersistentIdentifierBox(title: "Hotel Hoshizora Shinjuku"), planSource: nil),
            TripEvent(id: "demo-out", date: at(72 + 3 * 1440 - 240), kind: .checkOut, title: "Check out · Hotel Hoshizora Shinjuku",
                      detail: "Ref HSZ-48213", itemID: PersistentIdentifierBox(title: "Hotel Hoshizora Shinjuku"), planSource: nil),
          ]
          await TripReminders.sync(events: demo, place: "Tokyo", enabled: true, now: Date())
          return
        }
      #endif
      await TripReminders.sync(events: TripTimeline.events(items: items, plans: plans),
                               place: packs.first?.countryName ?? "Trip", enabled: reminders)
    }
    // Catch-up pass: when the app is open and the connection comes back, improve offline drafts.
    .task(id: "\(connectivity.isOnline)-\(connectivity.isGoodForCloud)-\(scenePhase == .active)") {
      guard scenePhase == .active, connectivity.isOnline,
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
      try? await Task.sleep(for: .seconds(2))   // let the connection settle
      guard !Task.isCancelled else { return }
      await CatchUpService.run(ai: ai, pack: packs.first)
      // Spending made offline: convert it at today's live rate.
      await ExpenseService.settle(ai: ai)
    }
    .onAppear {
      // First launch with an empty Vault → Welcome / set up your trip.
      showWelcome = !onboarded && items.isEmpty
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding") { showWelcome = true }
      #endif
    }
  }
}

/// Long-press actions on journey notifications: Show card · Done · Ask.
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  @MainActor weak var router: AppRouter?

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo
    let target = Self.target(action: response.actionIdentifier, info: info)
    await MainActor.run {
      switch target {
      case let .done(stepID): Task { await TripReminders.markDone(stepID) }
      case let .open(url): router?.open(url)
      case .home: router?.tab = .home
      }
    }
  }
}

extension NotificationActions {
  enum Target: Equatable {
    case done(String)
    case open(URL)
    case home
  }

  /// Where a notification action leads. Done marks the step; Ask opens Blue with the step in the field;
  /// the card button opens the ticket / taxi card / map; tapping the notification itself opens the trip.
  static func target(action: String, info: [AnyHashable: Any]) -> Target {
    let stepID = info["stepID"] as? String
    switch action {
    case "done":
      return stepID.map { .done($0) } ?? .home
    case "ask":
      var c = URLComponents(string: "travelcopilot://ask")!
      c.queryItems = [URLQueryItem(name: "q", value: info["ask"] as? String ?? "")]
      return c.url.map { .open($0) } ?? .home
    case "card":
      return (info["card"] as? String).flatMap(URL.init(string:)).map { .open($0) } ?? .home
    default:
      // A journey step opens the trip; anything else opens Home.
      return stepID != nil ? .open(URL(string: "travelcopilot://trip")!) : .home
    }
  }
}

#if DEBUG
  /// Sample spending for the simulator: the first evening settled at the Nov 28 rate, today's
  /// last two made offline and still waiting for the live rate.
  @MainActor
  enum SpendSample {
    static func seed(_ context: ModelContext) {
      guard ((try? context.fetchCount(FetchDescriptor<ExpenseItem>())) ?? 0) == 0 else { return }
      let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
      let rows: [(String, String, String?, Double, ExpenseCategory, String, Bool)] = [
        ("2026-12-03 16:30", "Keikyu Line", "京急線", 2020, .transport, "IC card", true),
        ("2026-12-03 19:00", "Omoide Yokocho", "思い出横丁", 4200, .food, "Cash", true),
        ("2026-12-03 21:10", "Lawson", "ローソン", 840, .food, "Cash", true),
        ("2026-12-04 10:05", "Toei Subway", "都営地下鉄", 220, .transport, "IC card", true),
        ("2026-12-04 11:20", "Senso-ji", "浅草寺", 1000, .sights, "Cash", true),
        ("2026-12-04 13:00", "Tokyo National Museum", "東京国立博物館", 1000, .sights, "Card", true),
        ("2026-12-04 15:30", "Don Quijote", "ドン・キホーテ", 3960, .shopping, "Card", false),
        ("2026-12-04 18:10", "Ichiran Shinjuku", "一蘭 新宿中央東口店", 1180, .food, "Cash", false),
      ]
      for (d, name, local, amount, cat, paid, settled) in rows {
        let e = ExpenseItem(spentAt: f.date(from: d)!, merchant: name, merchantLocal: local, amount: amount, currency: "JPY",
                            category: cat, paidWith: paid, source: "scan")
        if settled { e.rate = 149.6; e.homeAmount = (amount / 149.6 * 100).rounded() / 100; e.rateDate = f.date(from: "2026-11-28 12:00"); e.settled = true }
        context.insert(e)
      }
      if ExpenseService.savedRate == nil {
        ExpenseService.savedRate = FXRate(local: "JPY", home: "USD", localPerHome: 149.6, date: f.date(from: "2026-11-28 12:00")!)
      }
      try? context.save()
    }

    static func seedPlans(_ context: ModelContext) {
      let plans = (try? context.fetch(FetchDescriptor<TripPlan>())) ?? []
      guard !plans.contains(where: { $0.latitude != nil }) else { return }
      let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
      let rows: [(String, String, String, Double, Double)] = [
        ("2026-12-03 19:00", "Omoide Yokocho", "Dinner", 35.6933, 139.6995),
        ("2026-12-04 11:20", "Senso-ji", "Asakusa", 35.7148, 139.7967),
        ("2026-12-04 13:00", "Tokyo National Museum", "Ueno", 35.7188, 139.7765),
        ("2026-12-04 15:30", "Don Quijote", "Shinjuku", 35.6938, 139.7034),
        ("2026-12-04 18:10", "Ichiran Shinjuku", "Ramen", 35.6909, 139.7016),
        ("2026-12-05 10:00", "Meiji Jingu", "Harajuku", 35.6764, 139.6993),
        ("2026-12-05 14:00", "Shibuya Crossing", "Shibuya", 35.6595, 139.7005),
        ("2026-12-06 09:30", "Tsukiji Outer Market", "Breakfast", 35.6655, 139.7707),
        ("2026-12-06 13:00", "teamLab Planets", "Toyosu", 35.6491, 139.7898),
      ]
      for (d, title, kind, la, lo) in rows {
        let p = TripPlan(start: f.date(from: d)!, title: title)
        p.kind = kind; p.latitude = la; p.longitude = lo; p.remind = false
        context.insert(p)
      }
      try? context.save()
    }
  }
#endif
