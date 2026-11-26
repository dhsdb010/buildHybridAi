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
    private var feeds: [String: ([RoomMessage]) -> Void] = [:]

    var projectID: String? { nil }

    func start(uid: String, name: String, sink: SocialService) {
      self.sink = sink
      me = SocialUser(id: uid, handle: ProcessInfo.processInfo.arguments.contains("-socialNoID") ? "" : "alex_k", name: name)
      friends = ["mina", "jun_t", "kenta_w"].compactMap { people[$0] }
      requests = [FriendRequest(from: people["sora_k"]!, to: me, createdAt: Date())]
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
      feeds[room] = onChange; onChange(messages[room] ?? [])
      return { [weak self] in self?.feeds[room] = nil }
    }
    func send(_ text: String, in room: TripRoom, me: SocialUser, kind: RoomMessage.Kind) async throws {
      post(.init(id: UUID().uuidString, author: me.id, authorName: kind == .blue ? "Blue" : me.name, text: text,
                 sentAt: Date(), kind: kind, pending: false), room: room.id, last: true)
    }
    private func post(_ m: RoomMessage, room: String, last: Bool = false) {
      messages[room, default: []].append(m); feeds[room]?(messages[room] ?? [])
      if last, let i = rooms.firstIndex(where: { $0.id == room }) { rooms[i].lastText = "\(m.authorName): \(m.text)"; rooms[i].lastAt = Date(); push() }
    }
    func report(_ m: RoomMessage, in room: TripRoom, reason: String, me: SocialUser) async throws {}
    func deleteData(me: SocialUser) async throws {}
  }
#endif
