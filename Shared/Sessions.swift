// Agent sessions that may be waiting on the user.
// Hooks (App/Hook.swift) write one file per session; the app filters live ones into waiting.json for the widget.
import Foundation

enum SessionState: String, Codable {
    case idle        // open, nothing happening (fresh session, interrupted)
    case working     // agent is busy
    case approval    // permission dialog is up
    case question    // agent asked the user something
    case plan        // plan is ready for review
    case yourTurn    // turn finished, waiting for the next prompt

    var isBlocking: Bool { self == .approval || self == .question || self == .plan }
    var isWaiting: Bool { isBlocking || self == .yourTurn }
    var rank: Int { isBlocking ? 0 : 1 }

    var label: String {
        switch self {
        case .approval: return "Needs approval"
        case .question: return "Question for you"
        case .plan: return "Plan to review"
        case .yourTurn: return "Your turn"
        case .working: return "Working"
        case .idle: return "Idle"
        }
    }
}

struct AgentSession: Codable, Identifiable, Equatable {
    var agent: String        // "claude" | "codex"
    var sessionId: String
    var cwd: String
    var title: String?
    var state: SessionState
    var detail: String?
    var since: Date          // when the current state began
    var updated: Date
    var pid: Int32?          // agent process, for liveness checks

    var id: String { "\(agent)-\(sessionId)" }
    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? (agent == "claude" ? "Claude Code" : "Codex") : name
    }
    var agentName: String { agent == "claude" ? "Claude" : "Codex" }
}

enum SessionStore {
    static let blockingTTL: TimeInterval = 24 * 3600
    static let yourTurnTTL: TimeInterval = 6 * 3600

    static var supportDir: URL? { SharedStore.fileURL?.deletingLastPathComponent() }
    static var sessionsDir: URL? { supportDir?.appendingPathComponent("sessions", isDirectory: true) }
    static var waitingURL: URL? { supportDir?.appendingPathComponent("waiting.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }()

    static func fileURL(_ id: String) -> URL? {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return sessionsDir?.appendingPathComponent("\(safe).json")
    }

    static func load(_ id: String) -> AgentSession? {
        guard let url = fileURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AgentSession.self, from: data)
    }

    static func save(_ s: AgentSession) {
        guard let url = fileURL(s.id), let data = try? encoder.encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func remove(_ id: String) {
        if let url = fileURL(id) { try? FileManager.default.removeItem(at: url) }
    }

    static func loadAll() -> [AgentSession] {
        guard let dir = sessionsDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let d = try? Data(contentsOf: $0) else { return nil }
            return try? decoder.decode(AgentSession.self, from: d)
        }
    }

    /// Sessions worth showing: blockers first, then finished turns; oldest (most stuck) first.
    static func visible(_ all: [AgentSession], now: Date = Date()) -> [AgentSession] {
        all.filter { s in
            let age = now.timeIntervalSince(s.since)
            if s.state.isBlocking { return age < blockingTTL }
            if s.state == .yourTurn { return age < yourTurnTTL }
            return false
        }
        .sorted { ($0.state.rank, $0.since) < ($1.state.rank, $1.since) }
    }

    // waiting.json: the app's filtered, liveness-checked list for the widget.
    static func loadWaiting() -> [AgentSession] {
        guard let url = waitingURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([AgentSession].self, from: data)) ?? []
    }

    static func saveWaiting(_ list: [AgentSession]) {
        guard let url = waitingURL, let data = try? encoder.encode(list) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

func ago(_ d: Date, now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(d)))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}
