// Usage data sources. Run only in the (non-sandboxed) menu bar app.
import Foundation

struct HTTPError: Error {
    let status: Int
    let retryAfter: TimeInterval?
}

enum FetchOutcome {
    case ok(AgentUsage)
    case failed(reason: String, rateLimited: Bool = false, retryAfter: TimeInterval? = nil)
}

enum Fetch {
    static func json(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard code == 200 else {
            let retry = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw HTTPError(status: code, retryAfter: retry)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "json", code: 0)
        }
        return obj
    }

    static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func isoDate(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

enum ClaudeSource {
    /// Claude Code keeps its OAuth token in the Keychain ("Claude Code-credentials").
    static func token() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let tok = oauth["accessToken"] as? String else { return nil }
        return tok
    }

    static func fetch() async -> FetchOutcome {
        guard let tok = token() else { return .failed(reason: "Not signed in to Claude Code") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        do {
            let j = try await Fetch.json(req)
            func lim(_ k: String) -> Limit {
                let w = j[k] as? [String: Any]
                return Limit(percent: Fetch.num(w?["utilization"]), resetsAt: Fetch.isoDate(w?["resets_at"]))
            }
            return .ok(AgentUsage(fiveHour: lim("five_hour"), week: lim("seven_day"), fetchedAt: Date()))
        } catch let e as HTTPError where e.status == 401 {
            return .failed(reason: "Token expired, open Claude Code")
        } catch let e as HTTPError where e.status == 429 {
            return .failed(reason: "Rate limited", rateLimited: true, retryAfter: e.retryAfter)
        } catch let e as HTTPError {
            return .failed(reason: "Server error \(e.status)")
        } catch {
            return .failed(reason: "Offline")
        }
    }
}

enum CodexSource {
    static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")


    /// Live data from the ChatGPT backend (the same one Codex CLI uses).
    static func fetchAPI() async -> AgentUsage? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let tok = tokens["access_token"] as? String else { return nil }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        if let acc = tokens["account_id"] as? String { req.setValue(acc, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let j = try? await Fetch.json(req),
              let rl = j["rate_limit"] as? [String: Any] else { return nil }
        func lim(_ k: String) -> Limit {
            let w = rl[k] as? [String: Any]
            var reset: Date?
            if let at = Fetch.num(w?["reset_at"]) { reset = Date(timeIntervalSince1970: at) }
            else if let after = Fetch.num(w?["reset_after_seconds"]) { reset = Date().addingTimeInterval(after) }
            return Limit(percent: Fetch.num(w?["used_percent"]), resetsAt: reset)
        }
        let u = AgentUsage(fiveHour: lim("primary_window"), week: lim("secondary_window"), fetchedAt: Date())
        return u.fiveHour.percent == nil && u.week.percent == nil ? nil : u
    }

    /// Fallback: the latest rate_limits event from local Codex session logs.
    static func fromLogs() -> AgentUsage? {
        let dir = home.appendingPathComponent("sessions")
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, d))
        }
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            guard let fh = try? FileHandle(forReadingFrom: url) else { continue }
            let size = (try? fh.seekToEnd()) ?? 0
            try? fh.seek(toOffset: size > 1_000_000 ? size - 1_000_000 : 0)
            let data = fh.readDataToEndOfFile()
            try? fh.close()
            guard let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let rl = findRateLimits(obj) else { continue }
                func lim(_ k: String) -> Limit {
                    let w = rl[k] as? [String: Any]
                    let at = Fetch.num(w?["resets_at"]).map { Date(timeIntervalSince1970: $0) }
                    return Limit(percent: Fetch.num(w?["used_percent"]), resetsAt: at)
                }
                return AgentUsage(fiveHour: lim("primary"), week: lim("secondary"))
            }
        }
        return nil
    }

    static func findRateLimits(_ v: Any) -> [String: Any]? {
        if let d = v as? [String: Any] {
            if let rl = d["rate_limits"] as? [String: Any] { return rl }
            for (_, x) in d { if let r = findRateLimits(x) { return r } }
        } else if let a = v as? [Any] {
            for x in a { if let r = findRateLimits(x) { return r } }
        }
        return nil
    }
}
