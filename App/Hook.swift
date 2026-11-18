// Hook handler: `AgentMonitor --hook claude|codex` is called by the agent on lifecycle events.
// Reads the event JSON from stdin, updates the session's state file, prints nothing, always exits 0,
// so it never changes the agent's behavior.
import Darwin
import Foundation

enum Hook {
    static func run(agent: String) -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = j["session_id"] as? String,
              let event = j["hook_event_name"] as? String else { exit(0) }

        let now = Date()
        let id = "\(agent)-\(sid)"
        if event == "SessionEnd" { SessionStore.remove(id); exit(0) }

        let cwd = j["cwd"] as? String ?? ""
        var s = SessionStore.load(id)
            ?? AgentSession(agent: agent, sessionId: sid, cwd: cwd, state: .idle, since: now, updated: now)
        if !cwd.isEmpty { s.cwd = cwd }
        if let t = j["session_title"] as? String, !t.isEmpty { s.title = t }
        if agent == "codex", let t = codexThreadName(sid) { s.title = t }
        // Sessions run by the Claude desktop app carry its session id; it opens the exact session via deep link.
        if let h = ProcessInfo.processInfo.environment["CLAUDE_CODE_HOST_SESSION_ID"],
           h.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil {
            s.hostSessionId = h
        }
        s.pid = agentPID()

        let tool = j["tool_name"] as? String
        var next: (SessionState, String?)?

        switch event {
        case "SessionStart":
            next = (.idle, nil)
        case "UserPromptSubmit":
            next = (.working, nil)
            if s.title == nil, let p = j["prompt"] as? String { s.title = firstLine(p, 60) }
        case "PreToolUse":
            if tool == "AskUserQuestion" { next = (.question, questionText(j["tool_input"])) }
            else if tool == "ExitPlanMode" { next = (.plan, nil) }
            else { next = (.working, nil) }
        case "PostToolUse", "PostToolUseFailure":
            next = (.working, nil)
        case "PermissionRequest":
            next = (.approval, describe(tool, j["tool_input"]))
        case "Notification":
            switch j["notification_type"] as? String {
            case "permission_prompt":
                if !s.state.isBlocking { next = (.approval, j["message"] as? String) }
            case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                next = (.question, j["message"] as? String)
            default: break
            }
        case "Stop":
            let busy = !((j["background_tasks"] as? [Any]) ?? []).isEmpty
                || !((j["session_crons"] as? [Any]) ?? []).isEmpty
            next = busy ? (.working, nil) : (.yourTurn, firstLine(plain(j["last_assistant_message"] as? String ?? ""), 90))
        case "StopFailure":
            next = (.yourTurn, "Stopped with an error")
        case "Interrupt":
            next = (.idle, nil)
        default:
            break
        }

        guard let (state, detail) = next else { exit(0) }
        // A new finished turn or permission request is a fresh event even if the state looks the same.
        if state != s.state || event == "Stop" || event == "PermissionRequest" { s.since = now }
        s.state = state
        s.detail = (detail?.isEmpty == false) ? detail : nil
        s.updated = now
        SessionStore.save(s)
        exit(0)
    }

    // MARK: - Helpers

    /// Strips common Markdown so a summary reads as plain text: [text](url) → text, **bold**, `code`, # headings, list bullets.
    static func plain(_ s: String) -> String {
        var t = s
        let rules: [(String, String)] = [
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"(\*\*|__|`)"#, ""),
            (#"(?m)^\s{0,3}(#{1,6}|[-*+]|\d+\.)\s+"#, ""),
        ]
        for (p, r) in rules { t = t.replacingOccurrences(of: p, with: r, options: .regularExpression) }
        return t
    }

    /// Codex keeps thread names in ~/.codex/session_index.jsonl ({"id", "thread_name"}); the latest entry wins.
    static func codexThreadName(_ id: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl")
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        guard let text = String(data: fh.readDataToEndOfFile(), encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains(id) {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               o["id"] as? String == id, let name = o["thread_name"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    static func firstLine(_ s: String, _ max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count > max ? String(t.prefix(max - 1)) + "…" : t
    }

    static func describe(_ tool: String?, _ input: Any?) -> String? {
        guard let tool else { return nil }
        var name = tool
        if tool.hasPrefix("mcp__") {   // mcp__server__tool → server · tool
            let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
            if parts.count >= 3 { name = "\(parts[1]) · \(parts[2...].joined(separator: "_"))" }
        }
        let i = input as? [String: Any] ?? [:]
        if let cmd = i["command"] as? String { return "\(name): \(firstLine(cmd, 70))" }
        if let p = (i["file_path"] ?? i["path"]) as? String { return "\(name): \(URL(fileURLWithPath: p).lastPathComponent)" }
        if let u = i["url"] as? String { return "\(name): \(firstLine(u, 70))" }
        if let d = i["description"] as? String { return "\(name): \(firstLine(d, 70))" }
        return name
    }

    static func questionText(_ input: Any?) -> String? {
        let qs = (input as? [String: Any])?["questions"] as? [[String: Any]]
        return (qs?.first?["question"] as? String).map { firstLine($0, 90) }
    }

    /// The agent process: walk up past the shell(s) that ran this hook.
    static func agentPID() -> Int32 {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]
        var p = getppid()
        while shells.contains(Proc.name(p)), let pp = Proc.parent(p), pp > 1 { p = pp }
        return p
    }
}

enum Proc {
    static func parent(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func name(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, UInt32(buf.count))
        return String(cString: buf)
    }

    /// Controlling terminal of a process, e.g. "/dev/ttys003".
    static func tty(_ pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let raw = info.e_tdev                       // NODEV (all ones) = no controlling terminal
        guard raw != UInt32.max, raw != 0, let name = devname(dev_t(bitPattern: raw), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// pid and its ancestors, nearest first.
    static func ancestors(_ pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var p = pid
        while p > 1, out.count < 32 {
            out.append(p)
            guard let pp = parent(p) else { break }
            p = pp
        }
        return out
    }
}
