// Claude desktop app's own session records:
// ~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json
// Each maps the CLI session id (what hooks send) to the app's session id (what its deep links take),
// and tracks when the user last focused the session.
import Foundation

@MainActor
enum ClaudeDesktop {
    struct Info {
        let localId: String
        let lastFocusedAt: Date?
    }

    private static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    private static var pathByCli: [String: URL] = [:]
    private static var lastScan = Date.distantPast

    static let localIdPattern = #"^local_[A-Za-z0-9-]{1,64}$"#

    static func info(cliSessionId id: String) -> Info? {
        if pathByCli[id] == nil, Date().timeIntervalSince(lastScan) > 60 { scan() }
        guard let url = pathByCli[id], let o = read(url),
              let local = o["sessionId"] as? String, o["cliSessionId"] as? String == id else { return nil }
        let focused = (o["lastFocusedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Info(localId: local, lastFocusedAt: focused)
    }

    /// Indexes records touched in the last week (active sessions); there can be thousands of old ones.
    private static func scan() {
        lastScan = Date()
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        for case let url as URL in en {
            let name = url.lastPathComponent
            guard name.hasPrefix("local_"), url.pathExtension == "json" else { continue }
            let mod = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            guard mod > cutoff, let cli = read(url)?["cliSessionId"] as? String else { continue }
            pathByCli[cli] = url
        }
    }

    private static func read(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}
