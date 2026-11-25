import SwiftData
import SwiftUI

/// Chats (Figma 12 · screens 4 and 11): your private chat with Blue, requests, friends and one
/// room per shared trip. Rooms are friends-only.
struct ChatsView: View {
  @Environment(AppRouter.self) private var router
  @Environment(SocialService.self) private var social
  @State private var addingFriend = false
  @State private var newRoom = false
  @State private var openRoom: TripRoom?
  @State private var leaving: TripRoom?

  var body: some View {
    @Bindable var router = router
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        blueRow

        switch social.state {
        case .signedOut:
          MTALabel("Trip rooms").padding(.top, 6)
          SocialSignInCard()
        case .loading:
          ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        case .ready where !social.hasHandle:
          YourIDCard()
        case .ready:
          if !social.requests.isEmpty { requestsSection }
          friendsRow
          roomsSection
        }

        MTALabel("How rooms work").padding(.top, 6)
        VStack(alignment: .leading, spacing: 10) {
          rule("person.2", "One room per trip. Only friends can be added, so someone new gets a friend request first.")
          rule("at", "Blue answers in a room only when someone writes @Blue, and sees only the shared plan.")
          rule("bell.slash", "Mute or pin a room on this iPhone. Press and hold a message to report it.")
          rule("rectangle.portrait.and.arrow.right", "Leaving the trip leaves its room. If the owner leaves, the room closes.")
        }
        .padding(16)
        .background(MTA.raised, in: .rect(cornerRadius: 16))
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
    .background(MTA.surface)
    .navigationTitle("Chats")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if social.state == .ready && social.hasHandle {
        ToolbarItem(placement: .topBarTrailing) {
          Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Add friend")
        }
      }
    }
    .sheet(isPresented: $addingFriend) { AddFriendSheet() }
    .sheet(isPresented: $newRoom) { NewRoomSheet { room in openRoom = room } }
    .sheet(item: $router.inviteCode) { InviteRedeemSheet(code: $0.code) }
    .navigationDestination(item: $openRoom) { RoomView(roomID: $0.id) }
    .confirmationDialog(leaving.map { $0.owner == social.me?.id ? "Close \($0.name) for everyone?" : "Leave \($0.name)?" } ?? "",
                        isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }), titleVisibility: .visible) {
      Button(leaving?.owner == social.me?.id ? "Close room" : "Leave trip", role: .destructive) {
        if let r = leaving { Task { await social.leave(r) } }
      }
    }
  }

  private var blueRow: some View {
    Button { router.ask = AskRequest() } label: {
      HStack(spacing: 12) {
        Image(systemName: "asterisk").font(.system(size: 20, weight: .bold)).foregroundStyle(MTA.onColor)
          .frame(width: 44, height: 44).background(MTA.accent, in: .circle)
        VStack(alignment: .leading, spacing: 2) {
          Text("Blue").mta(.body1).foregroundStyle(MTA.text)
          Text("Just you · kept on this iPhone").mta(.body2).foregroundStyle(MTA.text2)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
      }
      .padding(.horizontal, 14).frame(minHeight: 68)
      .background(MTA.raised, in: .rect(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }

  private var requestsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      MTALabel("Requests · \(social.requests.count)")
      SocialCard {
        ForEach(social.requests) { r in
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
              PersonBadge(initial: r.from.initial)
              VStack(alignment: .leading, spacing: 2) {
                Text(r.from.name).mta(.body1).foregroundStyle(MTA.text)
                Text("@\(r.from.handle) wants to be friends").mta(.body2).foregroundStyle(MTA.text2)
              }
            }
            HStack(spacing: 8) {
              PillButton(title: "Accept") { Task { _ = await social.accept(r) } }
              PillButton(title: "Decline", filled: false) { Task { await social.decline(r) } }
              Spacer()
              Menu {
                Button("Block \(r.from.name)", systemImage: "hand.raised", role: .destructive) { Task { await social.block(r.from) } }
              } label: { Image(systemName: "ellipsis").foregroundStyle(MTA.text2).frame(width: 34, height: 34) }
              .accessibilityLabel("More for \(r.from.name)")
            }
            .padding(.leading, 48)
          }
          .padding(.vertical, 10)
        }
      }
    }
  }

  private var friendsRow: some View {
    VStack(alignment: .leading, spacing: 10) {
      MTALabel("Friends · \(social.friends.count)")
      NavigationLink { FriendsView() } label: {
        HStack(spacing: 10) {
          if social.friends.isEmpty {
            Image(systemName: "person.badge.plus").foregroundStyle(MTA.accent)
            Text("Add your first friend").mta(.body1).foregroundStyle(MTA.accent)
          } else {
            MemberStack(initials: social.friends.prefix(3).map(\.initial), firstIsMe: false)
            Text(social.friends.prefix(3).map(\.name).joined(separator: ", ")).mta(.body1).foregroundStyle(MTA.text).lineLimit(1)
          }
          Spacer()
          Text("See all").mta(.body2).foregroundStyle(MTA.text2)
          Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(MTA.raised, in: .rect(cornerRadius: 16))
      }
      .buttonStyle(.plain)
    }
  }

  private var roomsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      MTALabel("Trip rooms").padding(.top, 6)
      if social.rooms.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 22)).foregroundStyle(MTA.text2)
          Text("No trip rooms yet").mta(.body1).foregroundStyle(MTA.text)
          Text("Make a room for your trip, then add the friends you're going with.")
            .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MTA.subtle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
      } else {
        ForEach(social.sortedRooms) { room in
          NavigationLink { RoomView(roomID: room.id) } label: { RoomBlock(room: room) }
            .buttonStyle(.plain)
            .contextMenu {
              Button(social.isPinned(room.id) ? "Unpin" : "Pin", systemImage: social.isPinned(room.id) ? "pin.slash" : "pin") { social.togglePin(room.id) }
              Button(social.isMuted(room.id) ? "Unmute" : "Mute", systemImage: social.isMuted(room.id) ? "bell" : "bell.slash") { social.toggleMute(room.id) }
              Button(room.owner == social.me?.id ? "Close room" : "Leave trip", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = room }
            }
        }
      }
      Button { newRoom = true } label: { Label("Add", systemImage: "plus") }
        .buttonStyle(.mtaSecondary)
        .accessibilityLabel("Make a trip room")
    }
  }

  private func rule(_ symbol: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.text).frame(width: 22)
      Text(text).mta(.body2).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// One trip room in the list.
struct RoomBlock: View {
  let room: TripRoom
  @Environment(SocialService.self) private var social

  var body: some View {
    let me = social.me?.id ?? ""
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text(room.name).mta(.subheadNormal).foregroundStyle(MTA.text).lineLimit(1)
        if social.isPinned(room.id) { Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(MTA.text2) }
        if social.isMuted(room.id) { Image(systemName: "bell.slash.fill").font(.system(size: 12)).foregroundStyle(MTA.text2) }
        Spacer()
        Text(room.sortDate, format: .dateTime.month(.abbreviated).day()).mta(.body2).foregroundStyle(MTA.text2)
      }
      HStack(spacing: 10) {
        MemberStack(initials: orderedInitials(me: me))
        VStack(alignment: .leading, spacing: 2) {
          Text(room.membersText(me: me)).mta(.body2).foregroundStyle(MTA.text).lineLimit(1)
          Text(room.lastText ?? (room.members.count == 1 ? "Add the friends you're going with" : "Say hi"))
            .mta(.body2).foregroundStyle(MTA.text2).lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
      }
    }
    .padding(14)
    .background(MTA.raised, in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }

  private func orderedInitials(me: String) -> [String] {
    (room.members.filter { $0.id == me } + room.members.filter { $0.id != me }).map(\.initial)
  }
}

/// New trip room (Figma 12 · screen 16): name, which trip, and whether friends can edit.
struct NewRoomSheet: View {
  var onCreated: (TripRoom) -> Void
  @Environment(SocialService.self) private var social
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \VaultItem.startDate) private var items: [VaultItem]
  @State private var name = ""
  @State private var useTrip = true
  @State private var canEdit = 0
  @State private var busy = false

  private var trip: (title: String, city: String)? {
    let events = TripTimeline.events(items: items, plans: [])
    guard let range = TripTimeline.range(events) else { return nil }
    let city = TripSummary.city(destination: items.first { $0.kind == "flight" }?.destination) ?? "Trip"
    let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
    return ("\(city) · \(range.lowerBound.formatted(f))–\(range.upperBound.formatted(.dateTime.day()))", city)
  }
  private var suggested: String { trip.map { "\($0.city) trip" } ?? "Our trip" }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          MTALabel("Room name")
          TextField(suggested, text: $name)
            .mta(.body1).padding(.horizontal, 14).frame(minHeight: 50)
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.subtle, lineWidth: 1) }
          MTALabel("For which trip?").padding(.top, 6)
          SocialCard {
            if let trip {
              choice("airplane.departure", trip.title, "From your bookings", on: useTrip) { useTrip = true }
            }
            choice("map", "Just ideas, no dates yet", "Plan where to go together first", on: !useTrip || trip == nil) { useTrip = false }
          }
          MTALabel("Friends can").padding(.top, 6)
          MTASegmented(options: ["Edit the plan", "Only view"], selection: $canEdit)
          Text("The room shares this trip's day plan only. Your Vault, receipts, medical card and chats with Blue stay on this iPhone.")
            .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
          if let e = social.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .background(MTA.surface)
      .navigationTitle("New trip room")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) { Button("Create", action: create).fontWeight(.semibold).disabled(busy) }
      }
    }
  }

  private func choice(_ symbol: String, _ title: String, _ sub: String, on: Bool, tap: @escaping () -> Void) -> some View {
    Button(action: tap) {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 24).foregroundStyle(MTA.text)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).mta(.body1).foregroundStyle(MTA.text)
          Text(sub).mta(.body2).foregroundStyle(MTA.text2)
        }
        Spacer()
        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? MTA.accent : MTA.text2)
      }
      .frame(minHeight: 56).contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  private func create() {
    busy = true
    let n = name.trimmingCharacters(in: .whitespaces)
    Task {
      let room = await social.createRoom(name: n.isEmpty ? suggested : n, tripTitle: useTrip ? trip?.title : nil, friendsCanEdit: canEdit == 0)
      busy = false
      if let room { dismiss(); onCreated(room) }
    }
  }
}
