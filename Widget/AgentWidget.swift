// WidgetKit widget: reads the snapshot and draws the limits.
import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let s = context.isPreview ? .placeholder : (SharedStore.load() ?? .placeholder)
        completion(Entry(date: Date(), snapshot: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = SharedStore.load() ?? Snapshot()
        let now = Date()
        // One entry per minute so reset countdowns tick. Fresh data is pushed by the app.
        let entries = (0..<15).map { Entry(date: now.addingTimeInterval(Double($0) * 60), snapshot: s) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

@main
struct AgentMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentMonitorWidget", provider: Provider()) { entry in
            AgentWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Limits")
        .description("5-hour and weekly usage limits for Claude and Codex.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
