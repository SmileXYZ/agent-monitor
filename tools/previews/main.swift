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

// MARK: - README demo GIF frames (assembled into docs/demo.gif by render-previews.sh)

let gradient = LinearGradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.36),
                                       Color(red: 0.93, green: 0.55, blue: 0.38),
                                       Color(red: 0.45, green: 0.52, blue: 0.86)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)

struct CursorShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts: [CGPoint] = [.init(x: 0, y: 0), .init(x: 0, y: 17), .init(x: 4.5, y: 13), .init(x: 7.5, y: 20),
                              .init(x: 10.5, y: 18.8), .init(x: 7.6, y: 12), .init(x: 13, y: 12)]
        p.addLines(pts.map { CGPoint(x: r.minX + $0.x * r.width / 13, y: r.minY + $0.y * r.height / 20) })
        p.closeSubpath()
        return p
    }
}

struct DemoFrame: View {
    let sessions: [AgentSession]
    let cursor: CGPoint?
    let pressed: Bool
    let caption: Double     // 0...1 opacity
    var body: some View {
        let e = Entry(date: now, snapshot: demo, waiting: sessions)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 24) {
                    Card(width: 344, height: 162, dark: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            WaitingHeader(sessions: e.waiting)
                            WaitingList(sessions: e.waiting, now: e.date, max: 3)
                        }
                    }
                    Card(width: 162, height: 162, dark: true) { WaitingSmallView(entry: e) }
                }
                Text("Click a row → that exact session opens in Claude, Codex or your terminal")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .opacity(caption)
                    .frame(maxWidth: .infinity)
            }
            if let c = cursor {
                CursorShape().fill(.black)
                    .overlay(CursorShape().stroke(.white, lineWidth: 1.4))
                    .frame(width: 15, height: 23)
                    .scaleEffect(pressed ? 0.82 : 1, anchor: .topLeading)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: c.x, y: c.y)
            }
        }
        .padding(36)
        .frame(width: 638, height: 276, alignment: .topLeading)
        .background(gradient)
    }
}

func demoSession(_ agent: String, _ id: String, _ cwd: String, _ title: String, _ state: SessionState,
                 _ detail: String, _ minutesAgo: Double) -> AgentSession {
    AgentSession(agent: agent, sessionId: id, cwd: cwd, title: title, state: state, detail: detail,
                 since: now.addingTimeInterval(-minutesAgo * 60), updated: now)
}

@MainActor
func renderDemoFrames(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let landing = demoSession("codex", "d", "/landing", "Responsive hero", .yourTurn, "Hero section is responsive now", 41)
    let ship = demoSession("claude", "a", "/otwechator", "Ship the reviews digest", .approval, "Bash: npm run deploy", 1)
    let sync = demoSession("codex", "b", "/1cable", "Migrate the sync API", .question, "Keep the old API for v1 clients?", 1)
    let widget = demoSession("claude", "c", "/agent-monitor", "Waiting on You widget", .yourTurn, "Rows are clickable now", 0)

    let fps = 15.0
    let target = CGPoint(x: 150, y: 42)      // over the first row of the medium widget
    let start = CGPoint(x: 560, y: 250)
    var n = 0
    func emit(_ seconds: Double, _ list: [AgentSession], cursor: (Double) -> CGPoint? = { _ in nil },
              pressed: Bool = false, caption: (Double) -> Double = { _ in 0 }) {
        let count = Int(seconds * fps)
        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 1
            let r = ImageRenderer(content: DemoFrame(sessions: list, cursor: cursor(t), pressed: pressed, caption: caption(t)))
            r.scale = 1.5
            let img = r.nsImage!
            let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "f%04d.png", n)))
            n += 1
        }
    }
    func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
    func lerp(_ t: Double) -> CGPoint {
        let e = ease(t); return CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
    }

    emit(1.2, [landing])
    emit(1.2, [ship, landing])
    emit(1.4, [ship, sync, landing])
    emit(0.9, [ship, sync, landing], cursor: lerp)
    emit(0.25, [ship, sync, landing], cursor: { _ in target }, pressed: true)
    emit(0.4, [sync, landing], cursor: { _ in target }, caption: { $0 })
    emit(1.6, [sync, landing], cursor: { _ in target }, caption: { _ in 1 })
    emit(1.8, [sync, landing, widget], caption: { 1 - min(1, $0 * 2) })
    print("ok: \(n) frames in \(dir)")
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

MainActor.assumeIsolated { renderDemoFrames("build/demo-frames") }
