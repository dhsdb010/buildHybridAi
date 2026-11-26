import FirebaseCore
@preconcurrency import FirebaseFirestore
import Foundation

/// Friends and rooms in Cloud Firestore. Layout (rules in firebase/firestore.rules):
///   users/{uid}                      handle, name, inviteCode            (only you)
///   handles/{handle}                 uid, name                           (get by exact ID, no listing)
///   users/{uid}/friends/{friendUid}  handle, name, since, via            (you; the other side on accept/invite)
///   users/{uid}/blocked/{otherUid}   handle, name, since                 (only you)
///   friendRequests/{from}_{to}       from, to, fromHandle, fromName, toHandle, toName, createdAt
///   invites/{code}                   owner, ownerHandle, ownerName, createdAt, expiresAt
///   rooms/{roomId}                   name, owner, memberIds, members{uid:{name,handle,role}}, tripTitle,
///                                    friendsCanEdit, createdAt, lastText, lastAt
///   rooms/{roomId}/messages/{id}     author, authorName, text, kind, sentAt
///   reports/{id}                     reporter, roomId, messageId, author, text, reason, createdAt
@MainActor
final class FirestoreSocialBackend: SocialBackend {
  private var listeners: [ListenerRegistration] = []
  private var db: Firestore? { TravelCopilotApp.firebaseConfigured ? Firestore.firestore() : nil }

  var projectID: String? { TravelCopilotApp.firebaseConfigured ? FirebaseApp.app()?.options.projectID : nil }

  private func store() throws -> Firestore {
    guard let db else { throw SocialError(message: "Friends need Firebase set up (see SETUP.md).") }
    return db
  }

  // MARK: Session

  func start(uid: String, name: String, sink: SocialService) {
    stop()
    guard let db else { return }
    let me = db.collection("users").document(uid)
    listeners.append(me.addSnapshotListener { [weak sink] snap, _ in
      MainActor.assumeIsolated {
        let d = snap?.data()
        sink?.apply(handle: d?["handle"] as? String ?? "", name: d?["name"] as? String)
      }
    })
    listeners.append(me.collection("friends").addSnapshotListener { [weak sink] snap, _ in
      let list = snap?.documents.map { Self.user($0.documentID, $0.data()) } ?? []
      MainActor.assumeIsolated { sink?.apply(friends: list) }
    })
    listeners.append(me.collection("blocked").addSnapshotListener { [weak sink] snap, _ in
      let list = snap?.documents.map { Self.user($0.documentID, $0.data()) } ?? []
      MainActor.assumeIsolated { sink?.apply(blocked: list) }
    })
    let reqs = db.collection("friendRequests")
    listeners.append(reqs.whereField("to", isEqualTo: uid).addSnapshotListener { [weak sink] snap, _ in
      let list = snap?.documents.compactMap { Self.request($0.data()) } ?? []
      MainActor.assumeIsolated { sink?.apply(requests: list) }
    })
    listeners.append(reqs.whereField("from", isEqualTo: uid).addSnapshotListener { [weak sink] snap, _ in
      let list = snap?.documents.compactMap { Self.request($0.data()) } ?? []
      MainActor.assumeIsolated { sink?.apply(sent: list) }
    })
    listeners.append(db.collection("rooms").whereField("memberIds", arrayContains: uid).addSnapshotListener { [weak sink] snap, _ in
      let list = snap?.documents.compactMap { Self.room($0.documentID, $0.data()) } ?? []
      MainActor.assumeIsolated { sink?.apply(rooms: list) }
    })
    _ = name
  }

  func stop() { listeners.forEach { $0.remove() }; listeners = [] }

  // MARK: IDs

  func owner(of handle: String) async throws -> SocialUser? {
    let snap = try await store().collection("handles").document(handle).getDocument()
    guard let d = snap.data(), let uid = d["uid"] as? String else { return nil }
    return SocialUser(id: uid, handle: handle, name: d["name"] as? String ?? handle)
  }

  /// Claims the ID and frees your old one, in one transaction so two people can't take the same ID.
  func claim(handle: String, me: SocialUser) async throws {
    try await Self.claimTransaction(db: try store(), handle: handle, uid: me.id, name: me.name)
  }

  nonisolated private static func claimTransaction(db: Firestore, handle: String, uid: String, name: String) async throws {
    let userRef = db.collection("users").document(uid)
    let newRef = db.collection("handles").document(handle)
    let handles = db.collection("handles")
    _ = try await db.runTransaction { tx, errorPointer in
      do {
        let taken = try tx.getDocument(newRef)
        if taken.exists, taken.data()?["uid"] as? String != uid {
          errorPointer?.pointee = NSError(domain: "Social", code: 1, userInfo: [NSLocalizedDescriptionKey: "That ID was just taken. Try another."])
          return nil
        }
        let old = try tx.getDocument(userRef).data()?["handle"] as? String
        if let old, !old.isEmpty, old != handle { tx.deleteDocument(handles.document(old)) }
        tx.setData(["uid": uid, "name": name], forDocument: newRef)
        tx.setData(["handle": handle, "name": name, "createdAt": FieldValue.serverTimestamp()], forDocument: userRef, merge: true)
      } catch let e as NSError { errorPointer?.pointee = e }
      return nil
    }
  }

  // MARK: Friends

  func sendRequest(from: SocialUser, to: SocialUser) async throws {
    try await store().collection("friendRequests").document(FriendRequest.docID(from: from.id, to: to.id)).setData([
      "from": from.id, "to": to.id, "fromHandle": from.handle, "fromName": from.name,
      "toHandle": to.handle, "toName": to.name, "createdAt": FieldValue.serverTimestamp(),
    ])
  }

  func accept(_ r: FriendRequest, me: SocialUser) async throws {
    let db = try store()
    let b = db.batch()
    let via = "request:\(r.id)"
    b.setData(["handle": r.from.handle, "name": r.from.name, "since": FieldValue.serverTimestamp(), "via": via],
              forDocument: db.collection("users").document(me.id).collection("friends").document(r.from.id))
    b.setData(["handle": me.handle, "name": me.name, "since": FieldValue.serverTimestamp(), "via": via],
              forDocument: db.collection("users").document(r.from.id).collection("friends").document(me.id))
    b.deleteDocument(db.collection("friendRequests").document(r.id))
    try await b.commit()
  }

  func decline(_ r: FriendRequest) async throws {
    try await store().collection("friendRequests").document(r.id).delete()
  }

  func unfriend(_ uid: String, me: SocialUser) async throws {
    let db = try store()
    let b = db.batch()
    b.deleteDocument(db.collection("users").document(me.id).collection("friends").document(uid))
    b.deleteDocument(db.collection("users").document(uid).collection("friends").document(me.id))
    try await b.commit()
  }

  func block(_ user: SocialUser, me: SocialUser) async throws {
    let db = try store()
    let b = db.batch()
    b.setData(["handle": user.handle, "name": user.name, "since": FieldValue.serverTimestamp()],
              forDocument: db.collection("users").document(me.id).collection("blocked").document(user.id))
    b.deleteDocument(db.collection("users").document(me.id).collection("friends").document(user.id))
    b.deleteDocument(db.collection("users").document(user.id).collection("friends").document(me.id))
    b.deleteDocument(db.collection("friendRequests").document(FriendRequest.docID(from: user.id, to: me.id)))
    b.deleteDocument(db.collection("friendRequests").document(FriendRequest.docID(from: me.id, to: user.id)))
    try await b.commit()
  }

  func unblock(_ uid: String, me: SocialUser) async throws {
    try await store().collection("users").document(me.id).collection("blocked").document(uid).delete()
  }

  // MARK: Invites

  func invite(me: SocialUser, reset: Bool) async throws -> String {
    let db = try store()
    let userRef = db.collection("users").document(me.id)
    if !reset, let code = try await userRef.getDocument().data()?["inviteCode"] as? String,
       let inv = try await db.collection("invites").document(code).getDocument().data(),
       let exp = (inv["expiresAt"] as? Timestamp)?.dateValue(), exp > Date().addingTimeInterval(24 * 3600) {
      return code
    }
    let old = try await userRef.getDocument().data()?["inviteCode"] as? String
    let code = InviteCode.make()
    let b = db.batch()
    b.setData(["owner": me.id, "ownerHandle": me.handle, "ownerName": me.name,
               "createdAt": FieldValue.serverTimestamp(),
               "expiresAt": Timestamp(date: Date().addingTimeInterval(InviteCode.lifetime))],
              forDocument: db.collection("invites").document(code))
    b.setData(["inviteCode": code], forDocument: userRef, merge: true)
    if let old { b.deleteDocument(db.collection("invites").document(old)) }
    try await b.commit()
    return code
  }

  func redeem(code: String, me: SocialUser) async throws -> SocialUser {
    let db = try store()
    guard let d = try await db.collection("invites").document(code).getDocument().data(),
          let owner = d["owner"] as? String else { throw SocialError(message: "That code isn't valid any more. Ask for a new link.") }
    if let exp = (d["expiresAt"] as? Timestamp)?.dateValue(), exp < Date() {
      throw SocialError(message: "That invite has expired. Ask for a new link.")
    }
    guard owner != me.id else { throw SocialError(message: "That's your own invite.") }
    let friend = SocialUser(id: owner, handle: d["ownerHandle"] as? String ?? "", name: d["ownerName"] as? String ?? "")
    let b = db.batch()
    let via = "invite:\(code)"
    b.setData(["handle": friend.handle, "name": friend.name, "since": FieldValue.serverTimestamp(), "via": via],
              forDocument: db.collection("users").document(me.id).collection("friends").document(owner))
    b.setData(["handle": me.handle, "name": me.name, "since": FieldValue.serverTimestamp(), "via": via],
              forDocument: db.collection("users").document(owner).collection("friends").document(me.id))
    try await b.commit()
    return friend
  }

  // MARK: Rooms

  func createRoom(name: String, tripTitle: String?, friendsCanEdit: Bool, me: SocialUser) async throws -> TripRoom {
    let db = try store()
    let ref = db.collection("rooms").document()
    var data: [String: Any] = [
      "name": name, "owner": me.id, "memberIds": [me.id],
      "members": [me.id: ["name": me.name, "handle": me.handle, "role": TripRoom.Role.owner.rawValue]],
      "friendsCanEdit": friendsCanEdit, "createdAt": FieldValue.serverTimestamp(),
    ]
    if let tripTitle { data["tripTitle"] = tripTitle }
    try await ref.setData(data)
    try await system("\(me.name) made this room", room: ref.documentID, me: me)
    return TripRoom(id: ref.documentID, name: name, owner: me.id,
                    members: [.init(id: me.id, name: me.name, handle: me.handle, role: .owner)],
                    tripTitle: tripTitle, friendsCanEdit: friendsCanEdit, createdAt: Date())
  }

  /// One person per write, so the rules can check each one is the adder's friend.
  func add(_ people: [SocialUser], to room: TripRoom, me: SocialUser) async throws {
    let db = try store()
    let ref = db.collection("rooms").document(room.id)
    let role = room.friendsCanEdit ? TripRoom.Role.editor : .viewer
    for p in people {
      try await ref.updateData([
        "memberIds": FieldValue.arrayUnion([p.id]),
        "members.\(p.id)": ["name": p.name, "handle": p.handle, "role": role.rawValue],
      ])
    }
    let names = people.map(\.name)
    try await system("\(me.name) added \(ListFormatter.localizedString(byJoining: names))", room: room.id, me: me)
  }

  func remove(_ uid: String, from room: TripRoom, me: SocialUser) async throws {
    try await store().collection("rooms").document(room.id).updateData([
      "memberIds": FieldValue.arrayRemove([uid]), "members.\(uid)": FieldValue.delete(),
    ])
  }

  /// Leaving the trip leaves its room. The owner leaving deletes the room for everyone.
  func leave(_ room: TripRoom, me: SocialUser) async throws {
    let ref = try store().collection("rooms").document(room.id)
    if room.owner == me.id { try await ref.delete(); return }
    try await system("\(me.name) left", room: room.id, me: me)
    try await ref.updateData(["memberIds": FieldValue.arrayRemove([me.id]), "members.\(me.id)": FieldValue.delete()])
  }

  func listen(room: String, onChange: @escaping ([RoomMessage]) -> Void) -> () -> Void {
    guard let db else { return {} }
    let reg = db.collection("rooms").document(room).collection("messages")
      .order(by: "sentAt", descending: true).limit(to: 300)
      .addSnapshotListener(includeMetadataChanges: true) { snap, _ in
        let list: [RoomMessage] = snap?.documents.compactMap { doc in
          let d = doc.data(with: .estimate)
          guard let text = d["text"] as? String else { return nil }
          return RoomMessage(id: doc.documentID, author: d["author"] as? String ?? "", authorName: d["authorName"] as? String ?? "",
                             text: text, sentAt: (d["sentAt"] as? Timestamp)?.dateValue(),
                             kind: RoomMessage.Kind(rawValue: d["kind"] as? String ?? "text") ?? .text,
                             pending: doc.metadata.hasPendingWrites)
        }.reversed() ?? []
        MainActor.assumeIsolated { onChange(list) }
      }
    return { reg.remove() }
  }

  /// Not awaited past the local write: offline, it shows "Sends when you're back online".
  /// `.blue`: Blue's reply, posted by the asker's iPhone under the name "Blue".
  func send(_ text: String, in room: TripRoom, me: SocialUser, kind: RoomMessage.Kind) async throws {
    let db = try store()
    let roomRef = db.collection("rooms").document(room.id)
    let name = kind == .blue ? "Blue" : me.name
    let b = db.batch()
    b.setData(["author": me.id, "authorName": name, "text": text, "kind": kind.rawValue, "sentAt": FieldValue.serverTimestamp()],
              forDocument: roomRef.collection("messages").document())
    b.updateData(["lastText": "\(name): \(text.prefix(80))", "lastAt": FieldValue.serverTimestamp()], forDocument: roomRef)
    b.commit { _ in }
  }

  private func system(_ text: String, room: String, me: SocialUser) async throws {
    let db = try store()
    db.collection("rooms").document(room).collection("messages").document().setData(
      ["author": me.id, "authorName": me.name, "text": text, "kind": "system", "sentAt": FieldValue.serverTimestamp()]) { _ in }
  }

  func report(_ m: RoomMessage, in room: TripRoom, reason: String, me: SocialUser) async throws {
    try await store().collection("reports").document().setData([
      "reporter": me.id, "roomId": room.id, "messageId": m.id, "author": m.author, "text": m.text,
      "reason": reason, "createdAt": FieldValue.serverTimestamp(),
    ])
  }

  // MARK: Delete account

  func deleteData(me: SocialUser) async throws {
    let db = try store()
    let userRef = db.collection("users").document(me.id)
    for f in try await userRef.collection("friends").getDocuments().documents {
      try await unfriend(f.documentID, me: me)
    }
    for d in try await userRef.collection("blocked").getDocuments().documents { try await d.reference.delete() }
    let reqs = db.collection("friendRequests")
    for d in try await reqs.whereField("from", isEqualTo: me.id).getDocuments().documents { try await d.reference.delete() }
    for d in try await reqs.whereField("to", isEqualTo: me.id).getDocuments().documents { try await d.reference.delete() }
    for d in try await db.collection("rooms").whereField("memberIds", arrayContains: me.id).getDocuments().documents {
      if let r = Self.room(d.documentID, d.data()) { try await leave(r, me: me) }
    }
    let u = try await userRef.getDocument().data()
    if let code = u?["inviteCode"] as? String { try await db.collection("invites").document(code).delete() }
    if let h = u?["handle"] as? String, !h.isEmpty { try await db.collection("handles").document(h).delete() }
    try await userRef.delete()
  }

  // MARK: Decoding

  nonisolated static func user(_ id: String, _ d: [String: Any]) -> SocialUser {
    SocialUser(id: id, handle: d["handle"] as? String ?? "", name: d["name"] as? String ?? "")
  }

  nonisolated static func request(_ d: [String: Any]) -> FriendRequest? {
    guard let from = d["from"] as? String, let to = d["to"] as? String else { return nil }
    return FriendRequest(from: SocialUser(id: from, handle: d["fromHandle"] as? String ?? "", name: d["fromName"] as? String ?? ""),
                         to: SocialUser(id: to, handle: d["toHandle"] as? String ?? "", name: d["toName"] as? String ?? ""),
                         createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date())
  }

  nonisolated static func room(_ id: String, _ d: [String: Any]) -> TripRoom? {
    guard let name = d["name"] as? String, let owner = d["owner"] as? String else { return nil }
    let ids = d["memberIds"] as? [String] ?? []
    let map = d["members"] as? [String: [String: Any]] ?? [:]
    let members = ids.map { uid in
      let m = map[uid] ?? [:]
      return TripRoom.Member(id: uid, name: m["name"] as? String ?? "", handle: m["handle"] as? String ?? "",
                             role: TripRoom.Role(rawValue: m["role"] as? String ?? "") ?? .viewer)
    }
    return TripRoom(id: id, name: name, owner: owner, members: members, tripTitle: d["tripTitle"] as? String,
                    friendsCanEdit: d["friendsCanEdit"] as? Bool ?? true,
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    lastText: d["lastText"] as? String, lastAt: (d["lastAt"] as? Timestamp)?.dateValue())
  }
}
