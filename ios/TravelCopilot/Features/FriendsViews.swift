import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

// MARK: - Small parts

/// A friend's initial in a circle. Blue for you, black for everyone else (color means status in MTA).
struct PersonBadge: View {
  let initial: String
  var isMe = false
  var size: CGFloat = 36
  var body: some View {
    Text(initial).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(MTA.onColor)
      .frame(width: size, height: size).background(isMe ? MTA.accent : Color.black, in: .circle)
      .accessibilityHidden(true)
  }
}

/// Overlapping badges for a room's members.
struct MemberStack: View {
  let initials: [String]
  var firstIsMe = true
  var size: CGFloat = 30
  var body: some View {
    HStack(spacing: -size * 0.3) {
      ForEach(Array(initials.prefix(4).enumerated()), id: \.offset) { i, s in
        PersonBadge(initial: s, isMe: firstIsMe && i == 0, size: size).overlay { Circle().strokeBorder(MTA.raised, lineWidth: 2) }
      }
      if initials.count > 4 {
        Text("+\(initials.count - 4)").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(MTA.text)
          .frame(width: size, height: size).background(MTA.surface, in: .circle)
      }
    }
    .accessibilityHidden(true)
  }
}

struct PersonRow<Trailing: View>: View {
  let user: SocialUser
  @ViewBuilder var trailing: Trailing
  var body: some View {
    HStack(spacing: 12) {
      PersonBadge(initial: user.initial)
      VStack(alignment: .leading, spacing: 2) {
        Text(user.name.isEmpty ? "@\(user.handle)" : user.name).mta(.body1).foregroundStyle(MTA.text)
        Text("@\(user.handle)").mta(.body2).foregroundStyle(MTA.text2)
      }
      Spacer(minLength: 8)
      trailing
    }
    .frame(minHeight: 52)
    .accessibilityElement(children: .combine)
  }
}

struct SocialCard<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .padding(.horizontal, 14).padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTA.raised, in: .rect(cornerRadius: 16))
  }
}

/// "Sign in to plan with friends" (friends need an account; the solo trip doesn't).
struct SocialSignInCard: View {
  @State private var signingIn = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "person.2").font(.system(size: 22)).foregroundStyle(MTA.text2)
      Text("Plan with friends").mta(.body1).foregroundStyle(MTA.text)
      Text("Sign in to get your @ID, add friends and share trip rooms. Your trip on this iPhone stays private.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      Button("Sign in") { signingIn = true }.buttonStyle(.mtaPrimary).padding(.top, 4)
    }
    .padding(16)
    .background(MTA.raised, in: .rect(cornerRadius: 16))
    .sheet(isPresented: $signingIn) { SignInView(onDone: { signingIn = false }) }
  }
}

/// Small pill buttons used in rows (Accept, Decline, Add friend).
struct PillButton: View {
  let title: String
  var systemImage: String?
  var filled = true
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let systemImage { Image(systemName: systemImage) }
        Text(title)
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(filled ? MTA.onColor : MTA.accent)
      .padding(.horizontal, 14).frame(minHeight: 34)
      .background { if filled { Capsule().fill(MTA.accent) } else { Capsule().strokeBorder(MTA.accent, lineWidth: 1.5) } }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Your ID (Profile)

/// Claim a unique @ID. Friends find you only by the exact ID (Figma 12 · screen 7).
struct YourIDCard: View {
  @Environment(SocialService.self) private var social
  @Environment(AuthService.self) private var auth
  @State private var draft = ""
  @State private var available: Bool?
  @State private var busy = false
  @State private var editing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      MTALabel("Your ID")
      switch social.state {
      case .signedOut: SocialSignInCard()
      case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 60)
      case .ready:
        if social.hasHandle && !editing { claimed } else { claimForm }
      }
    }
  }

  private var claimed: some View {
    SocialCard {
      HStack {
        Text("@\(social.me?.handle ?? "")").mta(.headline).foregroundStyle(MTA.text)
        Spacer()
        Button("Change") { draft = social.me?.handle ?? ""; editing = true }.mta(.button2).foregroundStyle(MTA.accent)
      }
      .frame(minHeight: 54)
      NavigationLink { FriendsView() } label: {
        HStack {
          Text("Friends").mta(.body1).foregroundStyle(MTA.text)
          Spacer()
          Text("\(social.friends.count)").mta(.body2).foregroundStyle(MTA.text2)
          Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
        }
        .frame(minHeight: 48)
      }
      .buttonStyle(.plain)
    }
  }

  private var claimForm: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 4) {
        Text("@").mta(.body1).foregroundStyle(MTA.text2)
        TextField("your_id", text: $draft)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .mta(.body1).foregroundStyle(MTA.text)
        Spacer()
        if let p = Handle.problem(draft), !draft.isEmpty {
          Text(Handle.message(p)).mta(.body2).foregroundStyle(MTA.obstacle).lineLimit(1)
        } else if let available {
          Label(available ? "Available" : "Taken", systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
            .mta(.body2).foregroundStyle(available ? MTA.onTrack : MTA.urgent)
        }
      }
      .padding(.horizontal, 14).frame(minHeight: 50)
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 1.5) }
      Text("3–20 lowercase letters, numbers or _. Friends find you only by your exact ID; nobody can browse a list of people.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      Button(busy ? "Claiming…" : "Claim @\(Handle.normalize(draft))") {
        busy = true
        Task { if await social.claim(draft) { editing = false }; busy = false }
      }
      .buttonStyle(.mtaPrimary)
      .disabled(available != true || busy)
      if let e = social.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
    }
    .onAppear { if draft.isEmpty { draft = Handle.suggestion(name: social.me?.name ?? auth.account?.name ?? "") } }
    .task(id: draft) {
      available = nil
      guard Handle.isValid(draft) else { return }
      try? await Task.sleep(for: .milliseconds(350))
      available = await social.isAvailable(draft)
    }
  }
}

// MARK: - Friends list

struct FriendsView: View {
  @Environment(SocialService.self) private var social
  @State private var adding = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if social.friends.isEmpty {
          Text("No friends yet. Add someone by their @ID, a link, or their QR code.")
            .mta(.body2).foregroundStyle(MTA.text2)
        } else {
          SocialCard {
            ForEach(social.friends) { f in
              PersonRow(user: f) {
                Menu {
                  Button("Remove friend", systemImage: "person.badge.minus") { Task { await social.unfriend(f) } }
                  Button("Block \(f.name)", systemImage: "hand.raised", role: .destructive) { Task { await social.block(f) } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(MTA.text2).frame(width: 36, height: 36) }
                .accessibilityLabel("Options for \(f.name)")
              }
            }
          }
        }
        Button { adding = true } label: { Label("Add friend", systemImage: "person.badge.plus") }
          .buttonStyle(.mtaSecondary)
        if !social.blocked.isEmpty {
          MTALabel("Blocked").padding(.top, 6)
          SocialCard {
            ForEach(social.blocked) { b in
              PersonRow(user: b) { Button("Unblock") { Task { await social.unblock(b) } }.mta(.button2).foregroundStyle(MTA.accent) }
            }
          }
          Text("Blocked people can't send you requests or see you in rooms you add them to. They aren't told.")
            .mta(.body2).foregroundStyle(MTA.text2)
        }
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 32)
    }
    .background(MTA.surface)
    .navigationTitle("Friends")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $adding) { AddFriendSheet() }
  }
}

// MARK: - Add friend (ID · Link · QR)

/// Figma 12 · screens 8–10.
struct AddFriendSheet: View {
  enum Tab: Int { case id, link, qr }
  var start: Tab = .id
  var prefill = ""

  @Environment(SocialService.self) private var social
  @Environment(\.dismiss) private var dismiss
  @State private var tab = 0
  @State private var query = ""
  @State private var found: SocialUser?
  @State private var searched = false
  @State private var code = ""
  @State private var scanning = false
  @State private var added: SocialUser?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          MTASegmented(options: ["ID", "Link", "QR"], selection: $tab)
          if social.state != .ready { SocialSignInCard() }
          else if !social.hasHandle {
            Text("Claim your @ID in Profile first, so friends know it's you.").mta(.body2).foregroundStyle(MTA.text2)
            YourIDCard()
          } else {
            switch Tab(rawValue: tab) ?? .id {
            case .id: idTab
            case .link: linkTab
            case .qr: qrTab
            }
          }
          if let added {
            Label("You and \(added.name) are friends now", systemImage: "checkmark.circle.fill")
              .mta(.body2).foregroundStyle(MTA.onTrack)
          }
          if let e = social.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MTA.surface)
      .navigationTitle("Add friend")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
      .onAppear { tab = start.rawValue; if !prefill.isEmpty { query = prefill } }
      .sheet(isPresented: $scanning) {
        QRScanner { text in
          scanning = false
          if let c = InviteCode.parse(text) { Task { added = await social.redeem(c) } }
          else { social.error = "That QR isn't a Travel Copilot invite." }
        }
      }
    }
  }

  // ID: exact match only.
  private var idTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(MTA.text2)
        TextField("@their_id", text: $query)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .submitLabel(.search).onSubmit { Task { await search() } }
          .mta(.body1)
        if !query.isEmpty { Button("Clear", systemImage: "xmark") { query = ""; found = nil; searched = false }.labelStyle(.iconOnly).foregroundStyle(MTA.text2) }
      }
      .padding(.horizontal, 14).frame(minHeight: 50)
      .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(MTA.border, lineWidth: 1.5) }
      .task(id: query) {
        found = nil; searched = false
        guard Handle.isValid(query) else { return }
        try? await Task.sleep(for: .milliseconds(400))
        await search()
      }
      if let u = found {
        SocialCard {
          PersonRow(user: u) {
            if social.isFriend(u.id) { Text("Friends").mta(.body2).foregroundStyle(MTA.text2) }
            else if social.requestSent(to: u.id) { Label("Waiting", systemImage: "clock").mta(.body2).foregroundStyle(MTA.obstacle) }
            else { PillButton(title: "Send request") { Task { _ = await social.sendRequest(to: u) } } }
          }
        }
      } else if searched {
        VStack(alignment: .leading, spacing: 4) {
          Text("No one is @\(Handle.normalize(query))").mta(.body1).foregroundStyle(MTA.text)
          Text("IDs need an exact match. Check the spelling, or send an invite link instead.").mta(.body2).foregroundStyle(MTA.text2)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MTA.subtle, style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
      }
      if !social.sent.isEmpty {
        MTALabel("Sent")
        SocialCard {
          ForEach(social.sent) { r in
            PersonRow(user: r.to) { Label("Waiting", systemImage: "clock").mta(.body2).foregroundStyle(MTA.obstacle) }
          }
        }
      }
      Text("Requests need their OK. You can block someone at any time; blocked people can't send you requests.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func search() async {
    let q = query
    let u = await social.find(q)
    guard q == query else { return }
    found = u; searched = true
  }

  // Link: share it anywhere; opening it makes you friends.
  private var linkTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 12) {
        Label("Your invite link", systemImage: "link").mta(.body1).foregroundStyle(MTA.text)
        if let inv = social.invite {
          Text(inv.url.absoluteString.replacingOccurrences(of: "https://", with: ""))
            .mta(.body2).foregroundStyle(MTA.text).lineLimit(1).truncationMode(.middle)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(MTA.surface, in: .rect(cornerRadius: 12))
          HStack(spacing: 10) {
            ShareLink(item: inv.url, message: Text("Add me on Travel Copilot: @\(social.me?.handle ?? ""). Code \(InviteCode.display(inv.code))")) {
              Label("Share link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.mtaPrimary)
            Button { UIPasteboard.general.url = inv.url } label: { Label("Copy", systemImage: "doc.on.doc") }
              .buttonStyle(.mtaSecondary).frame(width: 120)
          }
        } else { ProgressView().frame(maxWidth: .infinity, minHeight: 50) }
      }
      .padding(16).background(MTA.raised, in: .rect(cornerRadius: 16))
      Text("Send it in Messages, KakaoTalk, WhatsApp or email. Anyone who opens it in the next 7 days becomes your friend.")
        .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
      Button("Reset link") { Task { await social.loadInvite(reset: true) } }.mta(.button2).foregroundStyle(MTA.accent)
      MTALabel("Got a code from a friend?").padding(.top, 6)
      HStack(spacing: 10) {
        TextField("Enter code", text: $code)
          .textInputAutocapitalization(.characters).autocorrectionDisabled()
          .mta(.body1).padding(.horizontal, 14).frame(minHeight: 50)
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.subtle, lineWidth: 1) }
        Button("Add") { Task { added = await social.redeem(code); if added != nil { code = "" } } }
          .buttonStyle(.mtaPrimary).frame(width: 90)
          .disabled(InviteCode.parse(code) == nil)
      }
      Text("If a link didn't open the app, type the 8-letter code at the end of it here.")
        .mta(.body2).foregroundStyle(MTA.text2)
    }
    .task { await social.loadInvite() }
  }

  // QR: show yours, or scan theirs.
  private var qrTab: some View {
    VStack(spacing: 14) {
      VStack(spacing: 10) {
        if let inv = social.invite {
          QRCodeImage(text: inv.url.absoluteString)
            .frame(width: 220, height: 220)
            .overlay { PersonBadge(initial: social.me?.initial ?? "", isMe: true, size: 44).overlay { Circle().strokeBorder(.white, lineWidth: 3) } }
            .accessibilityLabel("Your invite QR code")
        } else { ProgressView().frame(width: 220, height: 220) }
        Text("@\(social.me?.handle ?? "")").mta(.headline).foregroundStyle(MTA.text)
        Text(social.me?.name ?? "").mta(.body2).foregroundStyle(MTA.text2)
      }
      .padding(.vertical, 24).frame(maxWidth: .infinity)
      .background(MTA.raised, in: .rect(cornerRadius: 20))
      Text("Show this to a friend. They open Add friend → QR → Scan in Travel Copilot.")
        .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center)
      Button { scanning = true } label: { Label("Scan a friend's code", systemImage: "camera.viewfinder") }
        .buttonStyle(.mtaSecondary)
      Text("The QR holds your invite link, so resetting the link also changes the QR.")
        .mta(.body2).foregroundStyle(MTA.text2).frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { await social.loadInvite() }
  }
}

/// Black-on-white QR for a link, drawn on the iPhone.
struct QRCodeImage: View {
  let text: String
  var body: some View {
    if let img = Self.make(text) {
      Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
        .padding(10).background(.white, in: .rect(cornerRadius: 12))
    }
  }
  static func make(_ text: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8); f.correctionLevel = "H"   // H: the badge in the middle stays readable
    guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
  }
}

/// Camera scanner for a friend's QR (VisionKit). Not available in the simulator.
struct QRScanner: View {
  let onFound: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Group {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
          ScannerRepresentable(onFound: onFound).ignoresSafeArea()
        } else {
          VStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").font(.system(size: 40)).foregroundStyle(MTA.text2)
            Text("The camera scanner isn't available here. Ask your friend for their link or code instead.")
              .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center)
          }
          .padding(32)
        }
      }
      .navigationTitle("Scan a friend's code").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
    }
  }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
  let onFound: (String) -> Void
  func makeUIViewController(context: Context) -> DataScannerViewController {
    let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .fast,
                                       isHighlightingEnabled: true)
    vc.delegate = context.coordinator
    try? vc.startScanning()
    return vc
  }
  func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }
  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onFound: (String) -> Void
    private var done = false
    init(onFound: @escaping (String) -> Void) { self.onFound = onFound }
    func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
      guard !done else { return }
      for case let .barcode(b) in items { if let v = b.payloadStringValue { done = true; s.stopScanning(); onFound(v); return } }
    }
  }
}

// MARK: - Opening a friend's link

/// travelcopilot://i/CODE or https://…/i/CODE: become friends with whoever shared it.
struct InviteRedeemSheet: View {
  let code: String
  @Environment(SocialService.self) private var social
  @Environment(\.dismiss) private var dismiss
  @State private var friend: SocialUser?
  @State private var busy = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Image(systemName: friend == nil ? "person.badge.plus" : "checkmark.circle.fill")
          .font(.system(size: 44)).foregroundStyle(friend == nil ? MTA.accent : MTA.onTrack).padding(.top, 24)
        if let friend {
          Text("You and \(friend.name) are friends").mta(.headline).foregroundStyle(MTA.text).multilineTextAlignment(.center)
          Text("They can add you to trip rooms now, and you can add them.").mta(.body2).foregroundStyle(MTA.text2)
          Button("Done") { dismiss() }.buttonStyle(.mtaPrimary)
        } else if social.state != .ready {
          SocialSignInCard()
        } else if !social.hasHandle {
          Text("Claim your @ID first, so your friend knows it's you.").mta(.body2).foregroundStyle(MTA.text2)
          YourIDCard()
        } else {
          Text("Add a friend").mta(.headline).foregroundStyle(MTA.text)
          Text("Invite code \(InviteCode.display(code))").mta(.body1).foregroundStyle(MTA.text2)
          Text("You'll both see each other's name and @ID. Your trip, Vault and medical card stay private.")
            .mta(.body2).foregroundStyle(MTA.text2).multilineTextAlignment(.center)
          Button(busy ? "Adding…" : "Add friend") { busy = true; Task { friend = await social.redeem(code); busy = false } }
            .buttonStyle(.mtaPrimary).disabled(busy)
          Button("Not now") { dismiss() }.buttonStyle(.mtaSecondary)
        }
        if let e = social.error { Text(e).mta(.body2).foregroundStyle(MTA.urgent) }
        Spacer()
      }
      .mtaScreen()
      .background(MTA.surface)
      .navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
    }
  }
}
