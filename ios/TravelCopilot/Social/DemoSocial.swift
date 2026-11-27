#if DEBUG
  import Foundation

  /// `-socialDemo`: friends and rooms in memory, so the screens can be checked in the simulator
  /// without a second account. Nothing leaves the phone.
  @MainActor
  final class DemoSocialBackend: SocialBackend {
    private weak var sink: SocialService?
    private var me = SocialUser(id: "me", handle: "", name: "Alex")
    private let people: [String: SocialUser] = [
      "mina": .init(id: "u-mina", handle: "mina", name: "Mina"),
      "jun_t": .init(id: "u-jun", handle: "jun_t", name: "Jun"),
      "kenta_w": .init(id: "u-kenta", handle: "kenta_w", name: "Kenta"),
      "sora_k": .init(id: "u-sora", handle: "sora_k", name: "Sora"),
      "kenji": .init(id: "u-ken", handle: "kenji", name: "Ken"),
    ]
    private var friends: [SocialUser] = []
    private var requests: [FriendRequest] = []
    private var sent: [FriendRequest] = []
    private var blocked: [SocialUser] = []
    private var rooms: [TripRoom] = []
    private var messages: [String: [RoomMessage]] = [:]
    private var feeds: [String: [UUID: ([RoomMessage]) -> Void]] = [:]

    var projectID: String? { nil }

    func start(uid: String, name: String, sink: SocialService) {
      self.sink = sink
      me = SocialUser(id: uid, handle: ProcessInfo.processInfo.arguments.contains("-socialNoID") ? "" : "alex_k", name: name)
      friends = ["mina", "jun_t", "kenta_w"].compactMap { people[$0] }
      requests = [FriendRequest(from: people["sora_k"]!, to: me, createdAt: Date())]
      // `-socialDemoPlan`: a Tokyo room with Mina and Jun and a shared 3-day plan, to check editing.
      if ProcessInfo.processInfo.arguments.contains("-socialDemoPlan") {
        let id = "demo-room"
        rooms = [TripRoom(id: id, name: "Tokyo trip", owner: uid,
                          members: [.init(id: uid, name: name, handle: me.handle, role: .owner),
                                    .init(id: "u-mina", name: "Mina", handle: "mina", role: .editor),
                                    .init(id: "u-jun", name: "Jun", handle: "jun_t", role: .editor)],
                          tripTitle: "Tokyo · Dec 2–4", friendsCanEdit: true, createdAt: Date())]
        let cal = TripTimeline.calendar
        func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d, hour: h, minute: m))! }
        let rows: [(Date, String, String, String, Double, Double, Int)] = [
          (at(2, 15), "Hotel Hoshizora Shinjuku", "Check in", "Stay", 35.6938, 139.7034, 0),
          (at(2, 18, 30), "Shibuya Sky", "Night view from the rooftop", "See", 35.6585, 139.7023, 15),
          (at(2, 20), "Ichiran Shibuya", "Tonkotsu ramen", "Food", 35.6610, 139.7006, 10),
          (at(3, 10), "teamLab Planets", "Walk-through digital art", "See", 35.6491, 139.7898, 25),
          (at(3, 12, 30), "Toyosu market", "Street food and sushi", "Food", 35.6457, 139.7847, 20),
          (at(4, 10), "Senso-ji", "Tokyo's oldest temple", "See", 35.7148, 139.7967, 0),
          (at(4, 19), "Tokyo Skytree", "Night view", "See", 35.7101, 139.8107, 20)]
        plans[id] = rows.enumerated().map { i, r in
          SharedStop(id: "s\(i)", date: r.0, title: r.1, detail: r.2, kind: r.3, latitude: r.4, longitude: r.5,
                     addedBy: uid, addedByName: name, cost: r.6)
        }
        messages[id] = [RoomMessage(id: "m0", author: uid, authorName: name, text: "\(name) shared the plan · 3 days, 7 stops", sentAt: Date(), kind: .system, pending: false)]
      }
      push()
    }
    func stop() {}

    private func push() {
      sink?.apply(handle: me.handle, name: me.name)
      sink?.apply(friends: friends); sink?.apply(requests: requests); sink?.apply(sent: sent)
      sink?.apply(blocked: blocked); sink?.apply(rooms: rooms)
    }

    func owner(of handle: String) async throws -> SocialUser? { handle == me.handle ? me : people[handle] }
    func claim(handle: String, me: SocialUser) async throws {
      if people[handle] != nil { throw SocialError(message: "That ID was just taken. Try another.") }
      self.me.handle = handle; push()
    }
    func sendRequest(from: SocialUser, to: SocialUser) async throws { sent.append(.init(from: me, to: to, createdAt: Date())); push() }
    func accept(_ r: FriendRequest, me: SocialUser) async throws { friends.append(r.from); requests.removeAll { $0.id == r.id }; push() }
    func decline(_ r: FriendRequest) async throws { requests.removeAll { $0.id == r.id }; push() }
    func unfriend(_ uid: String, me: SocialUser) async throws { friends.removeAll { $0.id == uid }; push() }
    func block(_ user: SocialUser, me: SocialUser) async throws {
      blocked.append(user); friends.removeAll { $0.id == user.id }; requests.removeAll { $0.from.id == user.id }; push()
    }
    func unblock(_ uid: String, me: SocialUser) async throws { blocked.removeAll { $0.id == uid }; push() }
    func invite(me: SocialUser, reset: Bool) async throws -> String { reset ? InviteCode.make() : "K7Q4MZ2H" }
    func redeem(code: String, me: SocialUser) async throws -> SocialUser {
      let u = people["sora_k"]!
      if !friends.contains(u) { friends.append(u) }
      requests.removeAll { $0.from.id == u.id }; push(); return u
    }

    func createRoom(name: String, tripTitle: String?, friendsCanEdit: Bool, me: SocialUser) async throws -> TripRoom {
      let r = TripRoom(id: UUID().uuidString, name: name, owner: me.id,
                       members: [.init(id: me.id, name: me.name, handle: me.handle, role: .owner)],
                       tripTitle: tripTitle, friendsCanEdit: friendsCanEdit, createdAt: Date())
      rooms.append(r)
      post(.init(id: UUID().uuidString, author: me.id, authorName: me.name, text: "\(me.name) made this room", sentAt: Date(), kind: .system, pending: false), room: r.id)
      push(); return r
    }
    func add(_ people: [SocialUser], to room: TripRoom, me: SocialUser) async throws {
      guard let i = rooms.firstIndex(where: { $0.id == room.id }) else { return }
      for p in people { rooms[i].members.append(.init(id: p.id, name: p.name, handle: p.handle, role: room.friendsCanEdit ? .editor : .viewer)) }
      post(.init(id: UUID().uuidString, author: me.id, authorName: me.name,
                 text: "\(me.name) added \(ListFormatter.localizedString(byJoining: people.map(\.name)))", sentAt: Date(), kind: .system, pending: false), room: room.id)
      push()
      // A friend says hi a moment later (about this room, not anything made up).
      if let first = people.first {
        try? await Task.sleep(for: .seconds(2))
        post(.init(id: UUID().uuidString, author: first.id, authorName: first.name, text: "Hi everyone! Excited for \(room.name).",
                   sentAt: Date(), kind: .text, pending: false), room: room.id, last: true)
      }
    }
    func remove(_ uid: String, from room: TripRoom, me: SocialUser) async throws {
      if let i = rooms.firstIndex(where: { $0.id == room.id }) { rooms[i].members.removeAll { $0.id == uid } }; push()
    }
    func leave(_ room: TripRoom, me: SocialUser) async throws { rooms.removeAll { $0.id == room.id }; push() }

    func listen(room: String, onChange: @escaping ([RoomMessage]) -> Void) -> () -> Void {
      let token = UUID()
      feeds[room, default: [:]][token] = onChange; onChange(messages[room] ?? [])
      return { [weak self] in self?.feeds[room]?[token] = nil }
    }
    func send(_ text: String, in room: TripRoom, me: SocialUser, kind: RoomMessage.Kind) async throws {
      post(.init(id: UUID().uuidString, author: me.id, authorName: kind == .blue ? "Blue" : me.name, text: text,
                 sentAt: Date(), kind: kind, pending: false), room: room.id, last: true)
    }
    private func post(_ m: RoomMessage, room: String, last: Bool = false) {
      messages[room, default: []].append(m); feeds[room]?.values.forEach { $0(messages[room] ?? []) }
      if last, let i = rooms.firstIndex(where: { $0.id == room }) { rooms[i].lastText = "\(m.authorName): \(m.text)"; rooms[i].lastAt = Date(); push() }
    }
    func report(_ m: RoomMessage, in room: TripRoom, reason: String, me: SocialUser) async throws {}

    // Shared plan, in memory.
    private var plans: [String: [SharedStop]] = [:]
    private var planFeeds: [String: [UUID: ([SharedStop]) -> Void]] = [:]
    private func pushPlan(_ room: String) {
      let list = (plans[room] ?? []).sorted { $0.date < $1.date }
      planFeeds[room]?.values.forEach { $0(list) }
    }

    func listenPlan(room: String, onChange: @escaping ([SharedStop]) -> Void) -> () -> Void {
      let token = UUID()
      planFeeds[room, default: [:]][token] = onChange; pushPlan(room)
      return { [weak self] in self?.planFeeds[room]?[token] = nil }
    }
    func sharePlan(_ drafts: [SharedStop.Draft], in room: TripRoom, me: SocialUser) async throws {
      plans[room.id] = drafts.map { SharedStop(id: UUID().uuidString, date: $0.date, title: $0.title, detail: $0.detail, kind: $0.kind,
                                               latitude: $0.latitude, longitude: $0.longitude, addedBy: me.id, addedByName: me.name,
                                               cost: $0.cost, note: $0.note, address: $0.address) }
      pushPlan(room.id)
    }
    func saveStop(_ stop: SharedStop, in room: TripRoom, me: SocialUser) async throws {
      var s = stop; if s.id.isEmpty { s.id = UUID().uuidString }
      plans[room.id, default: []].removeAll { $0.id == s.id }; plans[room.id, default: []].append(s); pushPlan(room.id)
    }
    func removeStop(_ stop: SharedStop, in room: TripRoom, me: SocialUser) async throws {
      plans[room.id, default: []].removeAll { $0.id == stop.id }; pushPlan(room.id)
    }
    func note(_ text: String, in room: TripRoom, me: SocialUser) async throws {
      post(.init(id: UUID().uuidString, author: me.id, authorName: me.name, text: text, sentAt: Date(), kind: .system, pending: false), room: room.id)
    }
    func deleteData(me: SocialUser) async throws {}
  }
#endif
