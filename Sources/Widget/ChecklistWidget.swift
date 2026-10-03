import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry {
  let date: Date
  let glance: ChecklistGlance
}
struct ChecklistProvider: TimelineProvider {
  func placeholder(in context: Context) -> ChecklistEntry {
    ChecklistEntry(
      date: .now, glance: .init(remaining: 3, title: "Review checklist", updated: .now))
  }
  func getSnapshot(in context: Context, completion: @escaping (ChecklistEntry) -> Void) {
    completion(.init(date: .now, glance: ChecklistLocation.readGlance()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistEntry>) -> Void) {
    completion(
      Timeline(
        entries: [.init(date: .now, glance: ChecklistLocation.readGlance())],
        policy: .after(Date().addingTimeInterval(1800))))
  }
}
@main struct ChecklistWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "ChecklistGlance", provider: ChecklistProvider()) { entry in
      ChecklistWidgetView(entry: entry).containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "wristchecklist://open"))
    }.configurationDisplayName("Next task").description(
      "See remaining tasks and open your checklist."
    )
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
struct ChecklistWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ChecklistEntry
  var body: some View {
    switch family {
    case .accessoryCircular:
      VStack {
        Image(systemName: "checklist")
        Text("\(entry.glance.remaining)").font(.headline)
      }.accessibilityLabel("\(entry.glance.remaining) tasks remaining")
    case .accessoryInline:
      Label("\(entry.glance.remaining) tasks", systemImage: "checklist")
    default:
      VStack(alignment: .leading) {
        Text("\(entry.glance.remaining) remaining").font(.headline)
        Text(entry.glance.title ?? "Open your checklist").lineLimit(2).privacySensitive()
      }
    }
  }
}
