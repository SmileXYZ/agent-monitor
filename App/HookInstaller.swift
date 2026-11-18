// Adds/removes Agent Monitor hooks in Claude Code and Codex configs.
// Our entries are recognised by their command (".../AgentMonitor --hook <agent>"); other hooks are left alone.
import Foundation

struct HookTarget {
    let name: String
    let agent: String
    let path: URL
    let events: [(event: String, matcher: String?)]
}

enum HookInstaller {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static let claude = HookTarget(
        name: "Claude Code", agent: "claude",
        path: home.appendingPathComponent(".claude/settings.json"),
        events: [("SessionStart", nil), ("SessionEnd", nil), ("UserPromptSubmit", nil),
                 ("PreToolUse", "AskUserQuestion|ExitPlanMode"), ("PostToolUse", "*"), ("PostToolUseFailure", "*"),
                 ("PermissionRequest", "*"), ("Notification", nil), ("Stop", nil), ("StopFailure", nil)])

    static let codex = HookTarget(
        name: "Codex", agent: "codex",
        path: home.appendingPathComponent(".codex/hooks.json"),
        events: [("SessionStart", nil), ("SessionEnd", nil), ("UserPromptSubmit", nil),
                 ("PermissionRequest", nil), ("PostToolUse", nil), ("Stop", nil), ("Interrupt", nil)])

    static func command(_ agent: String) -> String {
        "'\(Bundle.main.executablePath ?? "/Applications/AgentMonitor.app/Contents/MacOS/AgentMonitor")' --hook \(agent)"
    }

    static func isOurs(_ handler: Any) -> Bool {
        guard let cmd = (handler as? [String: Any])?["command"] as? String else { return false }
        return cmd.contains("AgentMonitor") && cmd.contains("--hook")
    }

    static func read(_ t: HookTarget) -> [String: Any] {
        guard let d = try? Data(contentsOf: t.path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    static func isInstalled(_ t: HookTarget) -> Bool {
        let hooks = read(t)["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { g in (g["hooks"] as? [Any] ?? []).contains(where: isOurs) }
        }
    }

    /// Removes our handlers from every event; drops groups/events left empty.
    static func stripped(_ hooks: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { out[event] = value; continue }
            let kept: [[String: Any]] = groups.compactMap { g in
                guard let hs = g["hooks"] as? [Any] else { return g }
                let rest = hs.filter { !isOurs($0) }
                if rest.isEmpty { return nil }
                var g2 = g; g2["hooks"] = rest; return g2
            }
            if !kept.isEmpty { out[event] = kept }
        }
        return out
    }

    static func install(_ t: HookTarget) throws {
        var root = read(t)
        var hooks = stripped(root["hooks"] as? [String: Any] ?? [:])
        for (event, matcher) in t.events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(t.agent), "timeout": 5]]]
            if let matcher { group["matcher"] = matcher }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        root["hooks"] = hooks
        try write(root, to: t)
    }

    static func uninstall(_ t: HookTarget) throws {
        var root = read(t)
        let hooks = stripped(root["hooks"] as? [String: Any] ?? [:])
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try write(root, to: t)
    }

    private static func write(_ root: [String: Any], to t: HookTarget) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: t.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: t.path.path) {
            let backup = t.path.appendingPathExtension("agentmonitor-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: t.path, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: t.path, options: .atomic)
    }
}
