import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (and Lock Screen) control: one tap opens the emergency card.
struct EmergencyCardControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "dev.buildhybridai.travelcopilot.emergency-control") {
      ControlWidgetButton(action: ShowEmergencyCardIntent()) {
        Label("Emergency card", systemImage: "staroflife.fill")
      }
    }
    .displayName("Emergency card")
    .description("Opens your emergency medical card, in the local language.")
  }
}

/// Lock Screen widget: opens the card in one tap (after Face ID). It shows no medical details,
/// so nothing private is visible while the phone is locked.
struct EmergencyCardWidget: Widget {
  struct Entry: TimelineEntry { let date: Date }

  struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
      completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
  }

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "dev.buildhybridai.travelcopilot.emergency-widget", provider: Provider()) { _ in
      EmergencyWidgetView()
        .widgetURL(URL(string: "travelcopilot://emergency"))
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Emergency card")
    .description("One tap opens your emergency medical card. Shows no medical details on the Lock Screen.")
    .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
  }
}

struct EmergencyWidgetView: View {
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "staroflife.fill").font(.system(size: 26, weight: .semibold))
      }
      .accessibilityLabel("Emergency card")
    case .accessoryInline:
      Label("Emergency card", systemImage: "staroflife.fill")
    default:
      HStack(spacing: 8) {
        Image(systemName: "staroflife.fill").font(.system(size: 28, weight: .semibold))
        VStack(alignment: .leading, spacing: 1) {
          Text("Emergency card").font(.headline).widgetAccentable()
          Text("Tap to show · works offline").font(.caption)
        }
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .combine)
    }
  }
}
