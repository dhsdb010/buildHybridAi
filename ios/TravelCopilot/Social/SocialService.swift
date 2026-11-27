import Foundation
import Observation

/// Friends and trip rooms (Figma 12 · screens 7–18). Needs a signed-in account; the solo trip never
/// touches it. Backed by Firestore, or by an in-memory demo with `-socialDemo` (simulator screens).
@MainActor
@Observable
final class SocialService {
  enum State: Equatable { case signedOut, loading, ready }

  private(set) var state: State = .signedOut
  /// You. `handle` is empty until you claim an @ID.
  private(set) var me: SocialUser?
  private(set) var friends: [SocialUser] = []
  private(set) var requests: [FriendRequest] = []   // to you
  private(set) var sent: [FriendRequest] = []       // from you, not answered yet
  private(set) var blocked: [SocialUser] = []
  private(set) var rooms: [TripRoom] = []
  var error: String?

  var hasHandle: Bool { !(me?.handle.isEmpty ?? true) }
  var sortedRooms: [TripRoom] {
    rooms.sorted { a, b in
      let pa = isPinned(a.id), pb = isPinned(b.id)
      return pa != pb ? pa : a.sortDate > b.sortDate
    }
  }

  private let backend: SocialBackend
  /// `-socialDemo`: in-memory friends; ignores the real account.
  let isDemo: Bool

  init(backend: SocialBackend, isDemo: Bool = false) { self.backend = backend; self.isDemo = isDemo }

  static func live() -> SocialService {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-socialDemo") {
        let s = SocialService(backend: DemoSocialBackend(), isDemo: true)
        s.start(uid: "me", name: "Alex")
        return s
      }
    #endif
    return SocialService(backend: FirestoreSocialBackend())
  }

  // MARK: Session

  func start(uid: String, name: String) {
    guard me?.id != uid, !(isDemo && me != nil) else { return }
    state = .loading
    me = SocialUser(id: uid, handle: "", name: name)
    backend.start(uid: uid, name: name, sink: self)
  }

  func stop() {
    backend.stop()
    state = .signedOut; me = nil; friends = []; requests = []; sent = []; blocked = []; rooms = []
  }

  // Called by the backend as data arrives.
  func apply(handle: String?, name: String?) {
    if let handle { me?.handle = handle }
    if let name, !name.isEmpty { me?.name = name }
    if state == .loading { state = .ready }
  }
  func apply(friends: [SocialUser]) { self.friends = friends.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }
  func apply(requests: [FriendRequest]) { self.requests = requests.sorted { $0.createdAt > $1.createdAt } }
  func apply(sent: [FriendRequest]) { self.sent = sent }
  func apply(blocked: [SocialUser]) { self.blocked = blocked }
  func apply(rooms: [TripRoom]) { self.rooms = rooms }

  // MARK: Your ID

  func isAvailable(_ raw: String) async -> Bool {
    let h = Handle.normalize(raw)
    guard Handle.isValid(h) else { return false }
    if h == me?.handle { return true }
    return (try? await backend.owner(of: h)) == nil
  }

  func claim(_ raw: String) async -> Bool {
    let h = Handle.normalize(raw)
    guard let me, Handle.isValid(h) else { return false }
    return await run { try await self.backend.claim(handle: h, me: me) ; self.me?.handle = h }
  }

  // MARK: Friends

  /// Exact @ID only. Nobody can browse a list of people.
  func find(_ raw: String) async -> SocialUser? {
    let h = Handle.normalize(raw)
    guard Handle.isValid(h), h != me?.handle else { return nil }
    guard let u = try? await backend.owner(of: h), !isBlocked(u.id) else { return nil }
    return u
  }

  func isFriend(_ uid: String) -> Bool { friends.contains { $0.id == uid } }
  func isBlocked(_ uid: String) -> Bool { blocked.contains { $0.id == uid } }
  func requestSent(to uid: String) -> Bool { sent.contains { $0.to.id == uid } }

  func sendRequest(to user: SocialUser) async -> Bool {
    guard let me, hasHandle, !isFriend(user.id) else { return false }
    // They already asked you: accepting is the same as being friends.
    if let theirs = requests.first(where: { $0.from.id == user.id }) { return await accept(theirs) }
    return await run { try await self.backend.sendRequest(from: me, to: user) }
  }

  func accept(_ r: FriendRequest) async -> Bool {
    guard let me else { return false }
    return await run { try await self.backend.accept(r, me: me) }
  }

  func decline(_ r: FriendRequest) async { _ = await run { try await self.backend.decline(r) } }

  func unfriend(_ user: SocialUser) async { guard let me else { return }; _ = await run { try await self.backend.unfriend(user.id, me: me) } }

  /// Hides their messages and requests and ends the friendship. They aren't told.
  func block(_ user: SocialUser) async { guard let me else { return }; _ = await run { try await self.backend.block(user, me: me) } }
  func unblock(_ user: SocialUser) async { guard let me else { return }; _ = await run { try await self.backend.unblock(user.id, me: me) } }

  // MARK: Invite links and QR

  /// Your current friend invite (made once, kept for 7 days; Reset makes a new one).
  private(set) var invite: (code: String, url: URL)?

  func loadInvite(reset: Bool = false) async {
    guard let me, hasHandle else { return }
    if !reset, invite != nil { return }
    _ = await run {
      let code = try await self.backend.invite(me: me, reset: reset)
      self.invite = (code, InviteCode.link(code, projectID: self.backend.projectID))
    }
  }

  /// Opening a friend's link or code: you become friends right away.
  func redeem(_ code: String) async -> SocialUser? {
    guard let me, let c = InviteCode.parse(code) else { error = "That code isn't valid."; return nil }
    var friend: SocialUser?
    _ = await run { friend = try await self.backend.redeem(code: c, me: me) }
    return friend
  }

  // MARK: Rooms

  func createRoom(name: String, tripTitle: String?, friendsCanEdit: Bool) async -> TripRoom? {
    guard let me, hasHandle else { return nil }
    var room: TripRoom?
    _ = await run { room = try await self.backend.createRoom(name: name, tripTitle: tripTitle, friendsCanEdit: friendsCanEdit, me: me) }
    return room
  }

  /// Only friends can be added. Someone new needs a friend request first.
  func add(_ people: [SocialUser], to room: TripRoom) async -> Bool {
    guard let me else { return false }
    let ok = people.filter { isFriend($0.id) && room.member($0.id) == nil }
    guard !ok.isEmpty else { return false }
    return await run { try await self.backend.add(ok, to: room, me: me) }
  }

  func remove(_ uid: String, from room: TripRoom) async { guard let me, room.owner == me.id else { return }; _ = await run { try await self.backend.remove(uid, from: room, me: me) } }
  func leave(_ room: TripRoom) async { guard let me else { return }; _ = await run { try await self.backend.leave(room, me: me) } }

  func messages(_ room: TripRoom, onChange: @escaping ([RoomMessage]) -> Void) -> () -> Void {
    let hidden = Set(blocked.map(\.id))
    return backend.listen(room: room.id) { msgs in onChange(msgs.filter { !hidden.contains($0.author) }) }
  }

  func send(_ text: String, in room: TripRoom) async {
    let t = MessageFilter.clean(text.trimmingCharacters(in: .whitespacesAndNewlines))
    guard let me, !t.isEmpty else { return }
    _ = await run { try await self.backend.send(t, in: room, me: me, kind: .text) }
  }

  /// Rooms where Blue is answering right now (shows "Blue is typing…").
  private(set) var blueThinking: Set<String> = []

  /// @Blue: the asker's iPhone asks once (in the cloud, logged in the Routing Log) and posts the
  /// reply for everyone. Blue sees only this room's name, trip title and recent messages.
  func askBlue(_ text: String, in room: TripRoom, recent: [RoomMessage], plan: [SharedStop] = [], ai: AIService) async {
    guard let me else { return }
    blueThinking.insert(room.id); defer { blueThinking.remove(room.id) }
    let prompt = BlueInRoom.prompt(room: room, messages: recent, question: BlueInRoom.question(text), asker: me.name, plan: plan)
    do {
      let (reply, _) = try await ai.generate("Room · @Blue", kind: .open, prompt: prompt,
                                             instructions: BlueInRoom.instructions, as: BlueGroupReply.self)
      let answer = MessageFilter.clean(reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
      guard !answer.isEmpty else { return }
      _ = await run { try await self.backend.send(answer, in: room, me: me, kind: .blue) }
    } catch {
      self.error = ai.connectivity.isOnline
        ? "Blue couldn't answer just now. Try @Blue again in a moment."
        : "Blue answers in rooms when you're online. Ask again once you're connected."
    }
  }

  func report(_ m: RoomMessage, in room: TripRoom, reason: String) async -> Bool {
    guard let me else { return false }
    return await run { try await self.backend.report(m, in: room, reason: reason, me: me) }
  }

  // MARK: Shared plan

  /// Owners and editors change the plan; viewers suggest changes in the chat.
  func canEditPlan(_ room: TripRoom) -> Bool {
    guard let r = room.member(me?.id ?? "")?.role else { return false }
    return r == .owner || (r == .editor && room.friendsCanEdit)
  }

  func plan(_ room: TripRoom, onChange: @escaping ([SharedStop]) -> Void) -> () -> Void {
    backend.listenPlan(room: room.id, onChange: onChange)
  }

  /// The planner's result replaces the room's plan, and the chat says so.
  func sharePlan(_ drafts: [SharedStop.Draft], in room: TripRoom) async -> Bool {
    guard let me, canEditPlan(room), !drafts.isEmpty else { return false }
    return await run {
      try await self.backend.sharePlan(drafts, in: room, me: me)
      let days = Set(drafts.map { TripTimeline.calendar.startOfDay(for: $0.date) }).count
      try await self.backend.note("\(me.name) shared the plan · \(days) day\(days == 1 ? "" : "s"), \(drafts.count) stops", in: room, me: me)
    }
  }

  /// Add or change a stop. `note` goes in the chat ("Mina moved Tokyo Tower to Dec 6").
  func saveStop(_ stop: SharedStop, in room: TripRoom, note: String) async {
    guard let me, canEditPlan(room) else { return }
    var s = stop
    if s.addedBy.isEmpty { s.addedBy = me.id; s.addedByName = me.name }
    else if s.addedBy != me.id { s.editedByName = me.name }
    _ = await run {
      try await self.backend.saveStop(s, in: room, me: me)
      try await self.backend.note(note, in: room, me: me)
    }
  }

  func removeStop(_ stop: SharedStop, in room: TripRoom) async {
    guard let me, canEditPlan(room) else { return }
    _ = await run {
      try await self.backend.removeStop(stop, in: room, me: me)
      try await self.backend.note("\(me.name) removed \(stop.title)", in: room, me: me)
    }
  }

  /// Account deletion: your ID, friends, invites and memberships. Your old messages stay, unnamed.
  func deleteMyData() async { guard let me else { return }; _ = await run { try await self.backend.deleteData(me: me) }; stop() }

  // MARK: On this iPhone only

  func isPinned(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: "roomPinned-\(id)") }
  func isMuted(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: "roomMuted-\(id)") }
  func togglePin(_ id: String) { UserDefaults.standard.set(!isPinned(id), forKey: "roomPinned-\(id)"); rooms = rooms }
  func toggleMute(_ id: String) { UserDefaults.standard.set(!isMuted(id), forKey: "roomMuted-\(id)"); rooms = rooms }

  @discardableResult
  private func run(_ work: @escaping () async throws -> Void) async -> Bool {
    error = nil
    do { try await work(); return true } catch { self.error = Self.describe(error); return false }
  }

  static func describe(_ e: Error) -> String {
    if let s = e as? SocialError { return s.message }
    let ns = e as NSError
    if ns.domain == "FIRFirestoreErrorDomain" {
      switch ns.code {
      case 7: return "Not allowed. Check that you're friends, or try again."
      case 14: return "You're offline. It will go through when you're back online."
      default: break
      }
    }
    return e.localizedDescription
  }
}

struct SocialError: Error { let message: String }

/// Where friends and rooms are stored. Firestore in the app; in memory for `-socialDemo`.
@MainActor
protocol SocialBackend: AnyObject {
  var projectID: String? { get }
  func start(uid: String, name: String, sink: SocialService)
  func stop()
  func owner(of handle: String) async throws -> SocialUser?
  func claim(handle: String, me: SocialUser) async throws
  func sendRequest(from: SocialUser, to: SocialUser) async throws
  func accept(_ r: FriendRequest, me: SocialUser) async throws
  func decline(_ r: FriendRequest) async throws
  func unfriend(_ uid: String, me: SocialUser) async throws
  func block(_ user: SocialUser, me: SocialUser) async throws
  func unblock(_ uid: String, me: SocialUser) async throws
  func invite(me: SocialUser, reset: Bool) async throws -> String
  func redeem(code: String, me: SocialUser) async throws -> SocialUser
  func createRoom(name: String, tripTitle: String?, friendsCanEdit: Bool, me: SocialUser) async throws -> TripRoom
  func add(_ people: [SocialUser], to room: TripRoom, me: SocialUser) async throws
  func remove(_ uid: String, from room: TripRoom, me: SocialUser) async throws
  func leave(_ room: TripRoom, me: SocialUser) async throws
  func listen(room: String, onChange: @escaping ([RoomMessage]) -> Void) -> () -> Void
  func send(_ text: String, in room: TripRoom, me: SocialUser, kind: RoomMessage.Kind) async throws
  func report(_ m: RoomMessage, in room: TripRoom, reason: String, me: SocialUser) async throws
  func deleteData(me: SocialUser) async throws
  // Shared plan
  func listenPlan(room: String, onChange: @escaping ([SharedStop]) -> Void) -> () -> Void
  func sharePlan(_ drafts: [SharedStop.Draft], in room: TripRoom, me: SocialUser) async throws
  func saveStop(_ stop: SharedStop, in room: TripRoom, me: SocialUser) async throws
  func removeStop(_ stop: SharedStop, in room: TripRoom, me: SocialUser) async throws
  func note(_ text: String, in room: TripRoom, me: SocialUser) async throws
}
