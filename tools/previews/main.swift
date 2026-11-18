// Renders README images from the real widget views.
// Run: tools/render-previews.sh
import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
let now = Date()
let demo = Snapshot(
    claude: AgentUsage(fiveHour: Limit(percent: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                       week: Limit(percent: 61, resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600))),
    codex: AgentUsage(fiveHour: Limit(percent: 82, resetsAt: now.addingTimeInterval(47 * 60)),
                      week: Limit(percent: 23, resetsAt: now.addingTimeInterval(5 * 86400 + 2 * 3600))),
    updated: now)
let waitingDemo: [AgentSession] = [
    AgentSession(agent: "claude", sessionId: "a", cwd: "/otwechator", title: "Ship the reviews digest", state: .approval,
                 detail: "Bash: npm run deploy", since: now.addingTimeInterval(-4 * 60), updated: now),
    AgentSession(agent: "codex", sessionId: "b", cwd: "/1cable", title: "Migrate the sync API", state: .question,
                 detail: "Keep the old API for v1 clients?", since: now.addingTimeInterval(-9 * 60), updated: now),
    AgentSession(agent: "claude", sessionId: "c", cwd: "/agent-monitor", title: "Waiting on You widget", state: .yourTurn,
                 detail: "Rows are clickable now", since: now.addingTimeInterval(-26 * 60), updated: now),
    AgentSession(agent: "codex", sessionId: "d", cwd: "/landing", title: "Responsive hero", state: .yourTurn,
                 detail: "Hero section is responsive now", since: now.addingTimeInterval(-2 * 3600), updated: now),
]
let entry = Entry(date: now, snapshot: demo, waiting: waitingDemo)

struct Card<Content: View>: View {
    let width: CGFloat, height: CGFloat
    let dark: Bool
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(dark ? Color(white: 0.15) : Color(white: 0.97))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(dark ? 0.08 : 0.6), lineWidth: 0.5))
            .environment(\.colorScheme, dark ? .dark : .light)
            .foregroundStyle(dark ? .white : .black)
    }
}

func medium(_ dark: Bool) -> some View { Card(width: 344, height: 162, dark: dark) { MediumView(entry: entry) } }
func small(_ dark: Bool) -> some View { Card(width: 162, height: 162, dark: dark) { SmallView(entry: entry) } }
func large(_ dark: Bool) -> some View { Card(width: 344, height: 354, dark: dark) { LargeView(entry: entry) } }
func waitingMedium(_ dark: Bool) -> some View {
    Card(width: 344, height: 162, dark: dark) {
        VStack(alignment: .leading, spacing: 10) {
            WaitingHeader(sessions: entry.waiting)
            WaitingList(sessions: entry.waiting, now: entry.date, max: 3)
        }
    }
}
func waitingSmall(_ dark: Bool) -> some View { Card(width: 162, height: 162, dark: dark) { WaitingSmallView(entry: entry) } }

struct Backdrop<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(48)
            .background(
                LinearGradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.36),
                                        Color(red: 0.93, green: 0.55, blue: 0.38),
                                        Color(red: 0.45, green: 0.52, blue: 0.86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

@MainActor
func save<V: View>(_ view: V, _ name: String) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("failed: \(name)"); return
    }
    try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("ok: \(outDir)/\(name)")
}

MainActor.assumeIsolated {
    save(Backdrop {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) { medium(true); small(true) }
            HStack(spacing: 24) { medium(false); small(false) }
        }
    }, "hero.png")
    save(Backdrop {
        HStack(alignment: .top, spacing: 24) {
            large(true)
            VStack(alignment: .leading, spacing: 30) {
                waitingMedium(false)
                HStack(spacing: 20) { waitingSmall(true); waitingSmall(false) }
            }
        }
    }, "waiting.png")
}
