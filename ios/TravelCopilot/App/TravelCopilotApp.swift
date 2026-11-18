import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck

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
    #endif
    FirebaseApp.configure()
    return true
  }()

  let container: ModelContainer
  @State private var connectivity: Connectivity
  @State private var ai: AIService
  @State private var router = AppRouter()
  @State private var location = LocationService()

  init() {
    _ = Self.firebaseConfigured
    let container = try! ModelContainer(for: VaultItem.self, DestinationPack.self, RoutingEntry.self, TranslationEntry.self, TripPlan.self, Place.self, MapPack.self)
    let connectivity = Connectivity()
    self.container = container
    _connectivity = State(initialValue: connectivity)
    _ai = State(initialValue: AIService(connectivity: connectivity, context: container.mainContext))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(connectivity)
        .environment(ai)
        .environment(router)
        .environment(location)
    }
    .modelContainer(container)
  }
}

enum AppTab: Hashable { case home, trip, map, prepare, log }

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

  init() {
    #if DEBUG
      // Debug launch arguments for simulator checks (see SETUP.md).
      let d = UserDefaults.standard
      switch d.string(forKey: "tab") { case "trip": tab = .trip; case "map": tab = .map; case "prepare": tab = .prepare; case "log": tab = .log; default: break }
      if let q = d.string(forKey: "askQuestion") { ask = AskRequest(mode: 0, text: q, autoSubmit: true) }
      if let q = d.string(forKey: "sayText") { ask = AskRequest(mode: 1, text: q, autoSubmit: true) }
      switch d.string(forKey: "screen") { case "help": showHelp = true; case "settings": showSettings = true; case "ask": ask = AskRequest(); default: break }
    #endif
  }
}

struct RootView: View {
  @Environment(AppRouter.self) private var router
  @AppStorage("appearance") private var appearance = 0   // 0 system · 1 day · 2 night
  @AppStorage("onboarded") private var onboarded = false
  @Query private var items: [VaultItem]
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
    .sheet(item: $router.ask) { AskView(request: $0) }
    .sheet(isPresented: $router.showHelp) { HelpView() }
    .fullScreenCover(isPresented: $showWelcome) { WelcomeView() }
    .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
    .onAppear {
      // First launch with an empty Vault → Welcome / set up your trip.
      showWelcome = !onboarded && items.isEmpty
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding") { showWelcome = true }
      #endif
    }
  }
}
