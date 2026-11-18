// WidgetKit widgets: usage limits and "waiting on you".
import SwiftUI
import WidgetKit

/// One entry per minute so countdowns and "waiting for" ages tick. Fresh data is pushed by the app.
private func minuteEntries(_ make: (Date) -> Entry) -> Timeline<Entry> {
    let now = Date()
    let entries = (0..<15).map { make(now.addingTimeInterval(Double($0) * 60)) }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
}

private func liveEntry(_ date: Date) -> Entry {
    Entry(date: date,
          snapshot: SharedStore.load() ?? Snapshot(),
          waiting: SessionStore.visible(SessionStore.loadWaiting(), now: date))
}

extension AgentSession {
    static let demo: [AgentSession] = [
        AgentSession(agent: "claude", sessionId: "1", cwd: "/agent-monitor", state: .approval,
                     detail: "Bash: npm test", since: Date().addingTimeInterval(-180), updated: Date()),
        AgentSession(agent: "codex", sessionId: "2", cwd: "/1cable", state: .yourTurn,
                     detail: "Refactored the parser", since: Date().addingTimeInterval(-720), updated: Date()),
    ]
}

struct LimitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .placeholder, waiting: AgentSession.demo) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : liveEntry(Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(minuteEntries(liveEntry))
    }
}

struct WaitingProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), waiting: AgentSession.demo) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : liveEntry(Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(minuteEntries(liveEntry))
    }
}

struct AgentMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentMonitorWidget", provider: LimitsProvider()) { entry in
            AgentWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Limits")
        .description("5-hour and weekly usage limits for Claude and Codex. Large size also lists agents waiting on you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WaitingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaitingWidget", provider: WaitingProvider()) { entry in
            WaitingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Waiting on You")
        .description("Claude Code and Codex sessions that need approval, an answer, or your next prompt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AgentMonitorWidgets: WidgetBundle {
    var body: some Widget {
        AgentMonitorWidget()
        WaitingWidget()
    }
}
