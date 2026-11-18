// Shared model: the menu bar app writes a snapshot, the widget reads it.
import Foundation

struct Limit: Codable, Equatable {
    var percent: Double?   // 0...100
    var resetsAt: Date?

    /// If the window has already reset, treat usage as 0%.
    func effectivePercent(at now: Date = Date()) -> Double? {
        guard let p = percent else { return nil }
        if let r = resetsAt, r < now { return 0 }
        return p
    }
}

struct AgentUsage: Codable, Equatable {
    var fiveHour = Limit()
    var week = Limit()
    var error: String?
}

struct Snapshot: Codable, Equatable {
    var claude = AgentUsage(error: "No data yet")
    var codex = AgentUsage(error: "No data yet")
    var updated: Date?

    static let placeholder = Snapshot(
        claude: AgentUsage(fiveHour: Limit(percent: 34, resetsAt: Date().addingTimeInterval(2 * 3600 + 840)),
                           week: Limit(percent: 61, resetsAt: Date().addingTimeInterval(3 * 86400))),
        codex: AgentUsage(fiveHour: Limit(percent: 8, resetsAt: Date().addingTimeInterval(4 * 3600)),
                          week: Limit(percent: 72, resetsAt: Date().addingTimeInterval(86400 + 5 * 3600))),
        updated: Date())
}

enum SharedStore {
    /// ~/Library/Application Support/AgentMonitor/snapshot.json (the real home, not the sandbox container).
    /// The widget gets read access via a temporary-exception entitlement, so no App Group / Team ID is needed.
    static var fileURL: URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir))
            .appendingPathComponent("Library/Application Support/AgentMonitor/snapshot.json")
    }

    static func load() -> Snapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(Snapshot.self, from: data)
    }

    static func save(_ s: Snapshot) {
        guard let url = fileURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(s).write(to: url, options: .atomic)
    }
}

func remaining(_ d: Date?, now: Date) -> String {
    guard let d else { return "—" }
    let s = Int(d.timeIntervalSince(now))
    if s <= 0 { return "reset" }
    let days = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if days > 0 { return "\(days)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
