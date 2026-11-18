// Usage data sources. Run only in the (non-sandboxed) menu bar app.
import Foundation

struct HTTPError: Error {
    let status: Int
    let retryAfter: TimeInterval?
}

enum FetchOutcome {
    case ok(AgentUsage)
    /// `auth`: the user has to act (sign in, open Claude Code); old numbers would only hide that.
    case failed(reason: String, rateLimited: Bool = false, retryAfter: TimeInterval? = nil, auth: Bool = false)
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
    /// Claude Code keeps its OAuth credentials in the Keychain ("Claude Code-credentials").
    /// The CLI refreshes them only while it runs, so people who live in the Claude desktop app end up
    /// with an expired token. When it has expired, we refresh it the same way the CLI does and write
    /// it back, so the CLI keeps working with the rotated refresh token.
    static let service = "Claude Code-credentials"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static var lastRefreshAttempt = Date.distantPast

    enum TokenResult { case ok(String), missing, expired }

    static func readCredentials() -> [String: Any]? {
        guard let out = security(["find-generic-password", "-s", service, "-w"]), out.status == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: out.data) as? [String: Any]
    }

    static func token() async -> TokenResult {
        guard let creds = readCredentials(), let oauth = creds["claudeAiOauth"] as? [String: Any],
              let tok = oauth["accessToken"] as? String else { return .missing }
        let expiresAt = Fetch.num(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        guard let expiresAt, expiresAt < Date() else { return .ok(tok) }
        return await refresh() ?? .expired
    }

    /// Only after expiry (a running CLI refreshes a few minutes before), at most every 10 minutes.
    private static func refresh() async -> TokenResult? {
        guard Date().timeIntervalSince(lastRefreshAttempt) > 600 else { return nil }
        lastRefreshAttempt = Date()
        // Re-read right before: the CLI may have just refreshed it.
        guard let original = security(["find-generic-password", "-s", service, "-w"])?.data,
              var creds = try? JSONSerialization.jsonObject(with: original) as? [String: Any], var oauth = creds["claudeAiOauth"] as? [String: Any],
              let refreshToken = oauth["refreshToken"] as? String else { return nil }
        if let e = Fetch.num(oauth["expiresAt"]), e / 1000 > Date().timeIntervalSince1970,
           let tok = oauth["accessToken"] as? String { return .ok(tok) }

        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]
        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30
        guard let j = try? await Fetch.json(req), let access = j["access_token"] as? String,
              let expiresIn = Fetch.num(j["expires_in"]) else { return nil }

        oauth["accessToken"] = access
        if let r = j["refresh_token"] as? String { oauth["refreshToken"] = r }
        oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
        creds["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: creds, options: [.withoutEscapingSlashes]),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return .ok(access) }
        // Write the whole item back and check it reads back intact; if not, put the original back.
        // (Via argv like the CLI does for long items: `security -i` truncates lines over ~4 KB.)
        if !write(data) || readCredentials().map(NSDictionary.init) != NSDictionary(dictionary: creds) {
            NSLog("AgentMonitor: couldn't save the refreshed Claude token, restoring the Keychain item")
            _ = write(original.trimmingTrailingNewline)
        }
        return .ok(access)
    }

    private static func write(_ data: Data) -> Bool {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        return security(["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-X", hex])?.status == 0
    }

    private static func security(_ args: [String], input: Data? = nil) -> (status: Int32, data: Data)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        if input != nil { p.standardInput = inp }
        do { try p.run() } catch { return nil }
        if let input { inp.fileHandleForWriting.write(input); try? inp.fileHandleForWriting.close() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    static func fetch() async -> FetchOutcome {
        let tok: String
        switch await token() {
        case .ok(let t): tok = t
        case .missing: return .failed(reason: "Not signed in to Claude Code", auth: true)
        case .expired: return .failed(reason: "Token expired: run claude in Terminal", auth: true)
        }
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
            return .failed(reason: "Token expired: run claude in Terminal", auth: true)
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
        for (url, modified) in files.sorted(by: { $0.1 > $1.1 }).prefix(5) {
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
                // "as of" is the event's own time: later unrelated writes move the file's mtime,
                // which would make old numbers look newer than the last API fetch.
                return AgentUsage(fiveHour: lim("primary"), week: lim("secondary"),
                                  fetchedAt: Fetch.isoDate(obj["timestamp"]) ?? modified,
                                  staleReason: "from local logs")
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

private extension Data {
    var trimmingTrailingNewline: Data { last == 0x0A ? dropLast() : self }
}
