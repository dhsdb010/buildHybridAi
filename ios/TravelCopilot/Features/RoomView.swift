import SwiftUI

/// A trip room (Figma 12 · screens 5, 17, 18): members, "Who's coming?" until friends join,
/// messages, and the composer. Only the room's members can read or write it.
struct RoomView: View {
  let roomID: String
  @Environment(SocialService.self) private var social
  @Environment(AIService.self) private var ai
  @Environment(\.dismiss) private var dismiss
  @State private var messages: [RoomMessage] = []
  @State private var stopListening: (() -> Void)?
  @State private var text = ""
  @State private var addingPeople = false
  @State private var showInfo = false
  @State private var reporting: RoomMessage?
  @State private var plan: [SharedStop] = []
  @State private var stopPlan: (() -> Void)?
  @State private var planning = false
  @State private var showPlan = false

  private var room: TripRoom? { social.rooms.first { $0.id == roomID } }
  private var me: String { social.me?.id ?? "" }

  var body: some View {
    Group {
      if let room { content(room) } else {
        VStack(spacing: 8) {
          Text("This room is closed").mta(.body1).foregroundStyle(MTA.text)
          Text("The owner closed it, or you left.").mta(.body2).foregroundStyle(MTA.text2)
        }
      }
    }
    .background(MTA.surface)
    .navigationTitle(room?.name ?? "Room")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      if room != nil {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button { showInfo = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("Room info")
        }
      }
    }
    .navigationDestination(isPresented: $showInfo) { RoomInfoView(roomID: roomID) }
    .navigationDestination(isPresented: $showPlan) {
      SharedPlanView(roomID: roomID) { ask in text = ask; showPlan = false }
    }
    .fullScreenCover(isPresented: $planning) {
      if let room { PlanView(room: room, onClose: { planning = false }) }
    }
    .sheet(isPresented: $addingPeople) { if let room { AddPeopleSheet(room: room) } }
    .confirmationDialog("Report this message?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                        titleVisibility: .visible) {
      ForEach(["Harassment or hate", "Spam or scam", "Something else"], id: \.self) { reason in
        Button(reason) { if let m = reporting, let room { Task { _ = await social.report(m, in: room, reason: reason) } } }
      }
    } message: { Text("The Travel Copilot team gets the message and who sent it, and replies within 24 hours.") }
    .onAppear {
      guard stopListening == nil, let room else { return }
      stopListening = social.messages(room) { messages = $0 }
      stopPlan = social.plan(room) { plan = $0 }
    }
    .onDisappear { stopListening?(); stopListening = nil; stopPlan?(); stopPlan = nil }
  }

  @ViewBuilder
  private func content(_ room: TripRoom) -> some View {
    VStack(spacing: 0) {
      if !plan.isEmpty { planBar(room) }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            membersBar(room)
            if room.members.count == 1 && room.owner == me { WhoIsComing(room: room) }
            if plan.isEmpty { noPlanCard(room) }
            ForEach(messages) { m in bubble(m).id(m.id) }
            if social.blueThinking.contains(room.id) {
              HStack(spacing: 8) {
                BlueBadge(size: 26)
                Text("Blue is typing…").mta(.body2).foregroundStyle(MTA.text2)
              }
              .id("blue-typing")
            }
            if let e = social.error {
              Text(e).mta(.body2).foregroundStyle(MTA.obstacle).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
          }
          .mtaScreen().padding(.top, 8).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: messages.count) { _, _ in
          if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
        .onChange(of: social.blueThinking.contains(room.id)) { _, on in
          if on { withAnimation { proxy.scrollTo("blue-typing", anchor: .bottom) } }
        }
      }
      if room.member(me)?.role == .viewer {
        Text("You can view this room. The owner can let you edit.").mta(.body2).foregroundStyle(MTA.text2).padding(10)
      }
      composer(room)
    }
  }

  /// Before there's a plan (Figma 12 · screen 22): the same planner as planning alone, for the room.
  private func noPlanCard(_ room: TripRoom) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        BlueBadge(size: 32)
        Text("No plan yet").mta(.subheadNormal).foregroundStyle(MTA.text)
      }
      if social.canEditPlan(room) {
        Text("Plan it with Blue step by step: where, when, stay, eat, see. Everyone here gets the plan and can change it after.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
        Button("Plan with Blue") { planning = true }.buttonStyle(.mtaPrimary)
      } else {
        Text("The plan shows here once someone who can edit makes it with Blue. You can ask @Blue questions any time.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .background(MTA.raised, in: .rect(cornerRadius: 20))
  }

  /// Pinned on top once shared (Figma 12 · screen 25); opens the plan to edit together.
  private func planBar(_ room: TripRoom) -> some View {
    Button { showPlan = true } label: {
      HStack(spacing: 10) {
        Image(systemName: "calendar").font(.system(size: 18, weight: .semibold)).foregroundStyle(MTA.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text("Plan · \(room.name)").font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.text).lineLimit(1)
          Text(SharedPlan.summary(plan) + (social.canEditPlan(room) ? " · tap to edit" : "")).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
      }
      .padding(.horizontal, 12).frame(minHeight: 56)
      .background(MTA.raised, in: .rect(cornerRadius: 14))
      .padding(.horizontal, MTA.gutter).padding(.top, 6).padding(.bottom, 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Shared plan, \(SharedPlan.summary(plan))")
  }

  private func membersBar(_ room: TripRoom) -> some View {
    HStack(spacing: 10) {
      MemberStack(initials: (room.members.filter { $0.id == me } + room.members.filter { $0.id != me }).map(\.initial), size: 28)
      Text(room.members.count == 1 ? "Just you so far" : "\(room.members.count) in").mta(.body2).foregroundStyle(MTA.text)
      Spacer()
      Button("Add people") { addingPeople = true }.mta(.button2).foregroundStyle(MTA.accent)
    }
    .padding(.horizontal, 12).frame(minHeight: 48)
    .background(MTA.raised, in: .rect(cornerRadius: 14))
  }

  @ViewBuilder
  private func bubble(_ m: RoomMessage) -> some View {
    if m.kind == .blue {
      HStack(alignment: .bottom, spacing: 8) {
        BlueBadge(size: 26)
        VStack(alignment: .leading, spacing: 4) {
          Text("BLUE · FOR THE GROUP").mta(.label).foregroundStyle(MTA.accent)
          Text(room.map { Mentions.attributed(m.text, room: $0) } ?? AttributedString(m.text)).mta(.body1).foregroundStyle(MTA.text)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(MTA.raised, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MTA.accent.opacity(0.35), lineWidth: 1) }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 32)
      .accessibilityElement(children: .combine)
    } else if m.kind == .system {
      Text(m.text).mta(.body2).foregroundStyle(MTA.text2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
    } else if m.author == me {
      VStack(alignment: .trailing, spacing: 4) {
        Text(room.map { Mentions.attributed(m.text, room: $0) } ?? AttributedString(m.text)).mta(.body1).foregroundStyle(MTA.onColor)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(MTA.accent, in: .rect(cornerRadius: 18))
        if m.pending {
          Label("Sends when you're back online", systemImage: "clock").mta(.body2).foregroundStyle(MTA.obstacle)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
    } else {
      HStack(alignment: .bottom, spacing: 8) {
        PersonBadge(initial: String(m.authorName.prefix(1)).uppercased(), size: 26)
        VStack(alignment: .leading, spacing: 2) {
          Text(m.authorName).mta(.label).foregroundStyle(MTA.text2)
          Text(room.map { Mentions.attributed(m.text, room: $0) } ?? AttributedString(m.text)).mta(.body1).foregroundStyle(MTA.text)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(MTA.raised, in: .rect(cornerRadius: 18))
        .contextMenu {
          Button("Report", systemImage: "exclamationmark.bubble") { reporting = m }
          if let u = room?.member(m.author) {
            Button("Block \(u.name)", systemImage: "hand.raised", role: .destructive) {
              Task { await social.block(SocialUser(id: u.id, handle: u.handle, name: u.name)) }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 48)
    }
  }

  private func composer(_ room: TripRoom) -> some View {
    VStack(spacing: 8) {
      if let q = Mentions.activeQuery(in: text) {
        let list = Mentions.suggestions(query: q, room: room, me: me)
        if !list.isEmpty { mentionPanel(list, showLabel: q.isEmpty) }
      }
      composerRow(room)
    }
    .padding(.horizontal, MTA.gutter).padding(.vertical, 10)
    .background(MTA.surface)
    .disabled(room.member(me)?.role == .viewer)
    .animation(.easeOut(duration: 0.15), value: Mentions.activeQuery(in: text))
  }

  /// Typing @ shows Blue first, then the people in this room (Figma 12 · screens 19–20).
  private func mentionPanel(_ list: [Mentions.Suggestion], showLabel: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if showLabel { MTALabel("Mention").padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2) }
      ForEach(Array(list.prefix(6).enumerated()), id: \.element.id) { i, s in
        Button { text = Mentions.insert(s, into: text) } label: {
          HStack(spacing: 12) {
            if s.isBlue { BlueBadge(size: 36) } else { PersonBadge(initial: s.initial) }
            VStack(alignment: .leading, spacing: 2) {
              Text(s.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(MTA.text)
              Text(s.subtitle).mta(.body2).foregroundStyle(MTA.text2)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10).padding(.vertical, 8)
          .background(i == 0 ? MTA.raised : .clear, in: .rect(cornerRadius: 12))
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mention \(s.title)")
      }
    }
    .padding(8)
    .background(MTA.surface, in: .rect(cornerRadius: 18))
    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MTA.raised, lineWidth: 1) }
    .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
    .transition(.opacity.combined(with: .move(edge: .bottom)))
  }

  private func composerRow(_ room: TripRoom) -> some View {
    HStack(spacing: 10) {
      TextField("Message \(room.name)", text: $text, axis: .vertical)
        .mta(.body1).lineLimit(1...4)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MTA.subtle, lineWidth: 1) }
      Button("Send", systemImage: "paperplane.fill") {
        let t = text; text = ""
        Task {
          await social.send(t, in: room)
          // Only the asker's iPhone asks Blue, so the room gets one answer.
          if BlueInRoom.mentions(t) { await social.askBlue(t, in: room, recent: messages, plan: plan, ai: ai) }
        }
      }
      .labelStyle(.iconOnly).font(.system(size: 16, weight: .semibold)).foregroundStyle(MTA.onColor)
      .frame(width: 40, height: 40).background(MTA.accent, in: .circle)
      .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }
}

// MARK: - Friends-only picker with a To: search bar

/// Search your friends and tap to pick. Typing someone's exact @ID who isn't a friend yet offers
/// "Add friend" instead: only friends can join a room (Figma 12 · screens 12 and 17).
struct FriendPicker: View {
  let room: TripRoom
  @Binding var picked: [SocialUser]
  @Environment(SocialService.self) private var social
  @State private var query = ""
  @State private var stranger: SocialUser?
  @FocusState private var searching: Bool

  private var candidates: [SocialUser] {
    let q = Handle.normalize(query)
    return social.friends.filter { f in
      q.isEmpty || f.name.lowercased().contains(q) || f.handle.contains(q)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      toBar
      if !candidates.isEmpty {
        if !query.isEmpty { MTALabel("Friends") }
        VStack(spacing: 0) {
          ForEach(candidates) { f in
            let inRoom = room.member(f.id) != nil
            let on = picked.contains(f)
            Button { toggle(f) } label: {
              PersonRow(user: f) {
                if inRoom { Text("In this room").mta(.body2).foregroundStyle(MTA.text2) }
                else {
                  Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(on ? MTA.accent : MTA.text2)
                }
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain).disabled(inRoom)
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .background(MTA.surface, in: .rect(cornerRadius: 14))
      } else if social.friends.isEmpty && query.isEmpty {
        Text("No friends yet. Type someone's @ID to send a friend request.").mta(.body2).foregroundStyle(MTA.text2)
      }
      if let s = stranger {
        MTALabel("Not friends yet")
        PersonRow(user: s) {
          if social.requestSent(to: s.id) { Label("Requested", systemImage: "clock").mta(.body2).foregroundStyle(MTA.obstacle) }
          else { PillButton(title: "Add friend", systemImage: "person.badge.plus", filled: false) { Task { _ = await social.sendRequest(to: s) } } }
        }
        .padding(.horizontal, 12)
        .background(MTA.surface, in: .rect(cornerRadius: 14))
        Text("Only friends can join a trip room. \(s.name) can be added once they accept.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      } else if !query.isEmpty && Handle.isValid(query) {
        Text(candidates.isEmpty ? "No friend matches. Type someone's full @ID to send a friend request."
                                : "Looking for someone else? Type their full @ID.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      }
    }
    .task(id: query) {
      stranger = nil
      let h = Handle.normalize(query)
      guard Handle.isValid(h), !social.friends.contains(where: { $0.handle == h }) else { return }
      try? await Task.sleep(for: .milliseconds(400))
      if let u = await social.find(h), !social.isFriend(u.id) { stranger = u }
    }
  }

  // Chips wrap onto more lines with the search field after them; the whole bar focuses the field.
  private var toBar: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("To:").mta(.body1).foregroundStyle(MTA.text2)
      VStack(alignment: .leading, spacing: 8) {
        if !picked.isEmpty {
          WrapLayout(spacing: 6) {
            ForEach(picked) { p in
              Button { toggle(p) } label: {
                HStack(spacing: 4) { Text(p.name); Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                  .font(.system(size: 14, weight: .semibold)).foregroundStyle(MTA.onColor)
                  .padding(.horizontal, 10).padding(.vertical, 5).background(MTA.accent, in: .capsule)
              }
              .buttonStyle(.plain).accessibilityLabel("Remove \(p.name)")
            }
          }
        }
        TextField(picked.isEmpty ? "Search friends or @ID" : "Add more", text: $query)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($searching)
          .mta(.body1).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 12)
    .frame(minHeight: 48)
    .background(MTA.surface, in: .rect(cornerRadius: 14))
    .contentShape(.rect)
    .onTapGesture { searching = true }
  }

  private func toggle(_ f: SocialUser) {
    if let i = picked.firstIndex(of: f) { picked.remove(at: i) } else { picked.append(f); query = "" }
  }
}

/// Right after a room is made: "Who's coming?" (Figma 12 · screen 17).
struct WhoIsComing: View {
  let room: TripRoom
  @Environment(SocialService.self) private var social
  @State private var picked: [SocialUser] = []
  @State private var busy = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Who's coming?").mta(.headline).foregroundStyle(MTA.text)
      FriendPicker(room: room, picked: $picked)
      Button(busy ? "Adding…" : addTitle) {
        busy = true
        Task { if await social.add(picked, to: room) { picked = [] }; busy = false }
      }
      .buttonStyle(.mtaPrimary).disabled(picked.isEmpty || busy)
      Text("Not on your list? Type their @ID in the search and send a friend request first.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(MTA.raised, in: .rect(cornerRadius: 20))
  }

  private var addTitle: String {
    picked.isEmpty ? "Add friends" : "Add \(ListFormatter.localizedString(byJoining: picked.map(\.name)))"
  }
}

/// "Add people" from inside a room.
struct AddPeopleSheet: View {
  let room: TripRoom
  @Environment(SocialService.self) private var social
  @Environment(\.dismiss) private var dismiss
  @State private var picked: [SocialUser] = []
  @State private var busy = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          FriendPicker(room: room, picked: $picked)
          if let e = social.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
        }
        .padding(16)
        .background(MTA.raised, in: .rect(cornerRadius: 20))
        .mtaScreen().padding(.top, 8)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MTA.surface)
      .navigationTitle("Add to \(room.name)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button(picked.isEmpty ? "Add" : "Add (\(picked.count))") {
            busy = true
            Task { if await social.add(picked, to: room) { dismiss() }; busy = false }
          }
          .fontWeight(.semibold).disabled(picked.isEmpty || busy)
        }
      }
    }
  }
}

// MARK: - Room info

/// People and roles, mute and pin, block, report and leave (Figma 12 · screens 6 and 13).
struct RoomInfoView: View {
  let roomID: String
  @Environment(SocialService.self) private var social
  @Environment(\.dismiss) private var dismiss
  @State private var confirmLeave = false

  private var room: TripRoom? { social.rooms.first { $0.id == roomID } }

  var body: some View {
    ScrollView {
      if let room {
        let me = social.me?.id ?? ""
        let isOwner = room.owner == me
        VStack(alignment: .leading, spacing: 14) {
          VStack(spacing: 6) {
            Text(room.name).mta(.headline).foregroundStyle(MTA.text)
            Text([room.tripTitle, "\(room.members.count) people", isOwner ? "you own this room" : nil].compactMap { $0 }.joined(separator: " · "))
              .mta(.body2).foregroundStyle(MTA.text2)
          }
          .frame(maxWidth: .infinity)

          MTALabel("People")
          SocialCard {
            ForEach(room.members, id: \.id) { m in
              HStack(spacing: 12) {
                PersonBadge(initial: m.initial, isMe: m.id == me)
                Text(m.id == me ? "\(m.name) (you)" : m.name).mta(.body1).foregroundStyle(MTA.text)
                Spacer()
                Text(m.role.title).mta(.body2).foregroundStyle(MTA.text)
                  .padding(.horizontal, 10).padding(.vertical, 4)
                  .overlay { Capsule().strokeBorder(MTA.border, lineWidth: 1) }
                if m.id != me {
                  Menu {
                    if isOwner { Button("Remove from room", systemImage: "person.badge.minus") { Task { await social.remove(m.id, from: room) } } }
                    Button("Block \(m.name)", systemImage: "hand.raised", role: .destructive) {
                      Task { await social.block(SocialUser(id: m.id, handle: m.handle, name: m.name)) }
                    }
                  } label: { Image(systemName: "ellipsis").foregroundStyle(MTA.text2).frame(width: 30, height: 30) }
                  .accessibilityLabel("Options for \(m.name)")
                }
              }
              .frame(minHeight: 52)
            }
          }

          MTALabel("Notifications").padding(.top, 6)
          SocialCard {
            Toggle(isOn: Binding(get: { social.isMuted(room.id) }, set: { _ in social.toggleMute(room.id) })) {
              Label("Mute this room", systemImage: "bell.slash").mta(.body1).foregroundStyle(MTA.text)
            }
            .tint(MTA.onTrack).frame(minHeight: 50)
            Toggle(isOn: Binding(get: { social.isPinned(room.id) }, set: { _ in social.togglePin(room.id) })) {
              Label("Pin to the top", systemImage: "pin").mta(.body1).foregroundStyle(MTA.text)
            }
            .tint(MTA.onTrack).frame(minHeight: 50)
          }

          MTALabel("Safety").padding(.top, 6)
          SocialCard {
            HStack(spacing: 12) {
              Image(systemName: "exclamationmark.bubble").foregroundStyle(MTA.text)
              VStack(alignment: .leading, spacing: 2) {
                Text("Report a message").mta(.body1).foregroundStyle(MTA.text)
                Text("Press and hold any message").mta(.body2).foregroundStyle(MTA.text2)
              }
            }
            .frame(minHeight: 56)
            NavigationLink { FriendsView() } label: {
              HStack(spacing: 12) {
                Image(systemName: "hand.raised").foregroundStyle(MTA.text)
                Text("Blocked people").mta(.body1).foregroundStyle(MTA.text)
                Spacer()
                Text("\(social.blocked.count)").mta(.body2).foregroundStyle(MTA.text2)
                Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
              }
              .frame(minHeight: 50)
            }
            .buttonStyle(.plain)
          }
          Text("Reports go to the Travel Copilot team with the message and who sent it; we reply within 24 hours. Blocking hides their messages and requests. They aren't told.")
            .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Image(systemName: "asterisk").font(.system(size: 13, weight: .bold)).foregroundStyle(MTA.onColor)
                .frame(width: 24, height: 24).background(MTA.accent, in: .circle)
              Text("Blue in this room").mta(.body1).foregroundStyle(MTA.text)
            }
            Text("Answers when someone writes @Blue. Sees this trip's shared plan only, never your Vault, receipts or medical card.")
              .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
          }
          .padding(14).frame(maxWidth: .infinity, alignment: .leading)
          .background(MTA.raised, in: .rect(cornerRadius: 16))

          Button(isOwner ? "Close room for everyone" : "Leave trip", role: .destructive) { confirmLeave = true }
            .mta(.button2).foregroundStyle(MTA.urgent).frame(maxWidth: .infinity, minHeight: 48)
            .confirmationDialog(isOwner ? "Close \(room.name) for everyone?" : "Leave \(room.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
              Button(isOwner ? "Close room" : "Leave trip", role: .destructive) { Task { await social.leave(room); dismiss() } }
            }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 32)
      }
    }
    .background(MTA.surface)
    .navigationTitle("Room info")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Blue's mark in rooms: the app's blue asterisk.
struct BlueBadge: View {
  var size: CGFloat = 26
  var body: some View {
    Image(systemName: "asterisk").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(MTA.onColor)
      .frame(width: size, height: size).background(MTA.accent, in: .circle)
      .accessibilityLabel("Blue")
  }
}
