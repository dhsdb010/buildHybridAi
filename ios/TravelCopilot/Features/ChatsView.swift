import SwiftUI

/// Chats (Figma 12 · screen 4): your private chat with Blue, then one room per shared trip.
/// Trip rooms come with co-planning; until then the list explains how they'll work.
struct ChatsView: View {
  @Environment(AppRouter.self) private var router

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Button { router.ask = AskRequest() } label: {
          HStack(spacing: 12) {
            Image(systemName: "staroflife.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(MTA.onColor)
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

        MTALabel("Trip rooms").padding(.top, 6)
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 22)).foregroundStyle(MTA.text2)
          Text("No trip rooms yet").mta(.body1).foregroundStyle(MTA.text)
          Text("When you share a trip with friends, its group chat shows up here.")
            .mta(.body2).foregroundStyle(MTA.text2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MTA.subtle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }

        MTALabel("How rooms work").padding(.top, 6)
        VStack(alignment: .leading, spacing: 10) {
          rule("person.2", "One room per shared trip. Everyone on the trip is in it.")
          rule("at", "Blue answers in a room only when someone writes @Blue, and sees only the shared plan.")
          rule("bell.slash", "Mute a room, or get notified only for @mentions and votes.")
          rule("archivebox", "30 days after the trip, the room is archived. Leaving the trip leaves its room.")
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
  }

  private func rule(_ symbol: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.text).frame(width: 22)
      Text(text).mta(.body2).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
    }
  }
}
