// SwiftUI views for the widget. Also used by tools/previews to render README images.
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    var snapshot = Snapshot()
    var waiting: [AgentSession] = []
}

// MARK: - Views

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)   // terracotta
    static let codex = Color(red: 0.36, green: 0.62, blue: 0.98)    // sky blue
    static func level(_ p: Double?, tint: Color) -> Color {
        guard let p else { return .secondary }
        if p >= 90 { return Color(red: 1, green: 0.33, blue: 0.3) }
        if p >= 75 { return Color(red: 1, green: 0.66, blue: 0.2) }
        return tint
    }
}

func pctText(_ p: Double?) -> String { p.map { "\(Int($0.rounded()))%" } ?? "—" }

struct Ring: View {
    let limit: Limit
    let label: String
    let tint: Color
    let now: Date

    var body: some View {
        let p = limit.effectivePercent(at: now)
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.primary.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat((p ?? 0) / 100))
                    .stroke(Palette.level(p, tint: tint), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(pctText(p))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)
            VStack(spacing: 1) {
                Text(label).font(.system(size: 11, weight: .semibold))
                Text(remaining(limit.resetsAt, now: now))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AgentHeader: View {
    let name: String
    let tint: Color
    var note: String? = nil   // e.g. "as of 16:15" when showing last known numbers
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.system(size: 13, weight: .semibold, design: .rounded))
            if let note {
                Text(note).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct MediumView: View {
    let entry: Entry

    func column(_ name: String, _ tint: Color, _ u: AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHeader(name: name, tint: tint, note: u.staleNote)
            if let e = u.error {
                Text(e).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(spacing: 12) {
                    Ring(limit: u.fiveHour, label: "5 hours", tint: tint, now: entry.date)
                    Ring(limit: u.week, label: "week", tint: tint, now: entry.date)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            column("Claude", Palette.claude, entry.snapshot.claude)
            Rectangle().fill(.primary.opacity(0.1)).frame(width: 1)
            column("Codex", Palette.codex, entry.snapshot.codex)
        }
    }
}

struct SmallView: View {
    let entry: Entry

    func bar(_ label: String, _ l: Limit, _ tint: Color) -> some View {
        let p = l.effectivePercent(at: entry.date)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(pctText(p)).monospacedDigit().fontWeight(.semibold)
            }
            .font(.system(size: 10, weight: .medium))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.1))
                    Capsule().fill(Palette.level(p, tint: tint))
                        .frame(width: max(4, g.size.width * CGFloat((p ?? 0) / 100)))
                }
            }
            .frame(height: 5)
        }
    }

    func block(_ name: String, _ tint: Color, _ u: AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AgentHeader(name: name, tint: tint, note: u.staleNote)
            if let e = u.error {
                Text(e).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                bar("5h · " + remaining(u.fiveHour.resetsAt, now: entry.date), u.fiveHour, tint)
                bar("week · " + remaining(u.week.resetsAt, now: entry.date), u.week, tint)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            block("Claude", Palette.claude, entry.snapshot.claude)
            block("Codex", Palette.codex, entry.snapshot.codex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AgentWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: MediumView(entry: entry)
        }
    }
}

/// Large limits widget: rings on top, who's waiting below.
struct LargeView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MediumView(entry: entry).frame(height: 128)
            Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
            WaitingList(sessions: entry.waiting, now: entry.date, max: 4)
        }
    }
}

// MARK: - Waiting on you

enum StateColor {
    static let blocking = Color(red: 1, green: 0.33, blue: 0.3)
    static func of(_ s: SessionState) -> Color { s.isBlocking ? blocking : .secondary }
}

struct WaitingRow: View {
    let s: AgentSession
    let now: Date
    var body: some View {
        Link(destination: s.openURL) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(s.agent == "claude" ? Palette.claude : Palette.codex)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(s.displayTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(s.displayTitle == s.project ? ago(s.since, now: now) : "\(s.project) · \(ago(s.since, now: now))")
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Text(s.detail.map { "\(s.state.label) · \($0)" } ?? s.state.label)
                        .font(.system(size: 10.5, weight: s.state.isBlocking ? .semibold : .regular))
                        .foregroundStyle(StateColor.of(s.state))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AllClear: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Nothing is waiting on you").foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

struct WaitingList: View {
    let sessions: [AgentSession]
    let now: Date
    let max: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if sessions.isEmpty {
                AllClear()
            } else {
                ForEach(sessions.prefix(max)) { WaitingRow(s: $0, now: now) }
                if sessions.count > max {
                    Text("+\(sessions.count - max) more").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WaitingHeader: View {
    let sessions: [AgentSession]
    var body: some View {
        let blocking = sessions.filter { $0.state.isBlocking }.count
        HStack(alignment: .firstTextBaseline) {
            Text("Waiting on you").font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            if !sessions.isEmpty {
                Text("\(sessions.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(blocking > 0 ? StateColor.blocking : .secondary)
            }
        }
    }
}

struct WaitingSmallView: View {
    let entry: Entry
    var body: some View {
        let list = entry.waiting
        let blocking = list.filter { $0.state.isBlocking }.count
        VStack(alignment: .leading, spacing: 4) {
            Text("\(list.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(blocking > 0 ? StateColor.blocking : (list.isEmpty ? .secondary : .primary))
            Text(list.isEmpty ? "all clear" : "waiting on you")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            if let s = list.first {
                Text(s.displayTitle).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                Text(s.state.label).font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(StateColor.of(s.state)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(list.first?.openURL)   // small widgets support only one tap target
    }
}

struct WaitingWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        switch family {
        case .systemSmall:
            WaitingSmallView(entry: entry)
        default:
            VStack(alignment: .leading, spacing: 10) {
                WaitingHeader(sessions: entry.waiting)
                WaitingList(sessions: entry.waiting, now: entry.date, max: family == .systemLarge ? 8 : 3)
            }
        }
    }
}
