// SwiftUI views for the widget. Also used by tools/previews to render README images.
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
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
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}

struct MediumView: View {
    let entry: Entry

    func column(_ name: String, _ tint: Color, _ u: AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentHeader(name: name, tint: tint)
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
            AgentHeader(name: name, tint: tint)
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
        default: MediumView(entry: entry)
        }
    }
}
