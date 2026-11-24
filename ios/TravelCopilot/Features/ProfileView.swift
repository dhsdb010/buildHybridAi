import PhotosUI
import SwiftUI

/// Your photo or initial. Home's top-left button (Figma 12 · option B) and Profile's header.
struct ProfileAvatar: View {
  var size: CGFloat = 32
  @Environment(AuthService.self) private var auth
  @AppStorage(Profile.Key.name) private var name = ""
  /// Bumped when the photo changes, so the image reloads.
  @AppStorage("profilePhotoVersion") private var version = 0

  var body: some View {
    let initial = (Profile.firstName(account: auth.account?.name) ?? "").prefix(1).uppercased()
    Group {
      if let img = Profile.photo {
        Image(uiImage: img).resizable().scaledToFill()
      } else if !initial.isEmpty {
        Text(initial).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(MTA.onColor)
          .frame(maxWidth: .infinity, maxHeight: .infinity).background(MTA.accent)
      } else {
        Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(MTA.accent)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.circle)
    .id(version)
    .accessibilityLabel("Profile")
  }
}

/// Profile (Figma: 10 · Profile): who you are, where home is, how you travel. Kept on this iPhone.
struct ProfileView: View {
  @Environment(AuthService.self) private var auth
  @Environment(AppRouter.self) private var router
  @AppStorage(Profile.Key.name) private var name = ""
  @AppStorage(Profile.Key.city) private var city = ""
  @AppStorage(Profile.Key.airport) private var airport = ""
  @AppStorage(Profile.Key.currency) private var currency = ""
  @AppStorage(Profile.Key.languages) private var languages = ""
  @AppStorage(Profile.Key.likes) private var likes = ""
  @AppStorage(Profile.Key.pace) private var pace = ""
  @AppStorage(Profile.Key.skip) private var skip = ""
  @AppStorage(Profile.Key.countSteps) private var countSteps = false
  @AppStorage("spendBudget") private var budget = 1000.0
  @AppStorage("profilePhotoVersion") private var photoVersion = 0
  @State private var photoItem: PhotosPickerItem?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        // Settings lives here (Figma 12 · option B): Home's top right is for the group chat.
        NavigationLink { SettingsView() } label: {
          HStack(spacing: 12) {
            Image(systemName: "gearshape").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.text)
              .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
              Text("Settings").mta(.body1).foregroundStyle(MTA.text)
              Text("Network, appearance, privacy").mta(.body2).foregroundStyle(MTA.text2)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(MTA.text2)
          }
          .padding(.horizontal, 14).frame(minHeight: 60)
          .background(MTA.raised, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)

        MTALabel("About you").padding(.top, 6)
        card {
          field("Name on Home", $name, prompt: Profile.firstName(account: auth.account?.name) ?? "Your name")
          field("Home city", $city, prompt: "San Francisco")
          field("Home airport", $airport, prompt: "SFO", caps: true)
          field("Home currency", $currency, prompt: Locale.current.currency?.identifier ?? "USD", caps: true)
          field("Languages", $languages, prompt: "English", last: true)
        }

        MTALabel("How you travel").padding(.top, 6)
        WrapLayout(spacing: 8) {
          ForEach(Profile.likeOptions, id: \.self) { like in
            let on = selectedLikes.contains(like)
            Button { toggle(like) } label: {
              Text(like).mta(.button2)
                .foregroundStyle(on ? MTA.textInverse : MTA.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background { if on { Capsule().fill(MTA.inverse) } else { Capsule().strokeBorder(MTA.border, lineWidth: 1.5) } }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }
        card {
          HStack {
            Text("Pace").mta(.body1).foregroundStyle(MTA.text)
            Spacer()
            Picker("Pace", selection: $pace) {
              Text("Not set").tag("")
              ForEach(Profile.paces, id: \.self) { Text($0).tag($0) }
            }
            .tint(MTA.text)
          }
          .frame(minHeight: 46).overlay(alignment: .bottom) { divider }
          HStack {
            Text("Trip budget").mta(.body1).foregroundStyle(MTA.text)
            Spacer()
            TextField("1000", value: $budget, format: .number.precision(.fractionLength(0)))
              .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(Spend.homeCurrency).mta(.body2).foregroundStyle(MTA.text2)
          }
          .frame(minHeight: 46).overlay(alignment: .bottom) { divider }
          field("Skip", $skip, prompt: "Long queues", last: true)
        }
        Text("Blue uses this when it plans with you. Only these words are sent, never your name or home.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)

        MTALabel("Safety").padding(.top, 6)
        card {
          Button { router.showHelp = true } label: {
            HStack {
              Text("Medical info card").mta(.body1).foregroundStyle(MTA.text)
              Spacer()
              Text("Open ›").mta(.body2).foregroundStyle(MTA.accent)
            }
            .frame(minHeight: 46).overlay(alignment: .bottom) { divider }
          }
          .buttonStyle(.plain)
          Toggle(isOn: $countSteps) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Count steps on trips").mta(.body1).foregroundStyle(MTA.text)
              Text("From Health, for your trip summary").mta(.body2).foregroundStyle(MTA.text2)
            }
          }
          .tint(MTA.onTrack).frame(minHeight: 52)
        }

        Text("Kept on this iPhone. Used to plan with you and for your trip summary. When you plan with friends, only your name and photo are shown to them.")
          .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)

        if !isEmpty {
          Button("Clear profile", role: .destructive) { clear() }
            .mta(.button2).foregroundStyle(MTA.urgent).frame(maxWidth: .infinity, minHeight: 44)
        }
      }
      .mtaScreen().padding(.top, 8).padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.interactively)
    .background(MTA.surface)
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: photoItem) { _, item in
      Task {
        let data = try? await item?.loadTransferable(type: Data.self)
        Profile.savePhoto(data)
        photoVersion += 1
      }
    }
  }

  // MARK: Parts

  private var header: some View {
    HStack(spacing: 14) {
      PhotosPicker(selection: $photoItem, matching: .images) {
        ProfileAvatar(size: 64)
          .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(MTA.onColor)
              .frame(width: 22, height: 22).background(MTA.text, in: .circle)
              .overlay { Circle().strokeBorder(MTA.surface, lineWidth: 2) }
          }
      }
      .accessibilityLabel("Change photo")
      VStack(alignment: .leading, spacing: 2) {
        Text(Profile.firstName(account: auth.account?.name) ?? "Your profile").mta(.headline).foregroundStyle(MTA.text)
        Text(auth.account.map { "Signed in with \($0.provider) · tap the photo to change it" } ?? "Tap the photo to add one")
          .mta(.body2).foregroundStyle(MTA.text2)
      }
    }
  }

  private var divider: some View { Rectangle().fill(MTA.subtle.opacity(0.4)).frame(height: 1) }

  private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    VStack(spacing: 0) { content() }
      .padding(.horizontal, 14).padding(.vertical, 2)
      .background(MTA.raised, in: .rect(cornerRadius: 16))
  }

  private func field(_ title: String, _ text: Binding<String>, prompt: String, caps: Bool = false, last: Bool = false) -> some View {
    HStack {
      Text(title).mta(.body1).foregroundStyle(MTA.text)
      Spacer(minLength: 12)
      TextField(prompt, text: text)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(caps ? .characters : .words)
        .autocorrectionDisabled(caps)
        .mta(.body1).foregroundStyle(MTA.text)
    }
    .frame(minHeight: 46)
    .overlay(alignment: .bottom) { if !last { divider } }
  }

  private var selectedLikes: [String] { likes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
  private func toggle(_ like: String) {
    var l = selectedLikes
    if let i = l.firstIndex(of: like) { l.remove(at: i) } else { l.append(like) }
    likes = l.joined(separator: ", ")
  }
  private var isEmpty: Bool { [name, city, airport, currency, languages, likes, pace, skip].allSatisfy(\.isEmpty) && Profile.photo == nil }
  private func clear() {
    for k in [Profile.Key.name, Profile.Key.city, Profile.Key.airport, Profile.Key.currency, Profile.Key.languages,
              Profile.Key.likes, Profile.Key.pace, Profile.Key.skip] { UserDefaults.standard.removeObject(forKey: k) }
    Profile.savePhoto(nil); photoVersion += 1
  }
}

/// Lays chips out in rows, wrapping to the next line.
struct WrapLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
    for s in subviews {
      let size = s.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
      x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
    }
    return CGSize(width: min(widest, width), height: y + row)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
    for s in subviews {
      let size = s.sizeThatFits(.unspecified)
      if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
      s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing; row = max(row, size.height)
    }
  }
}
