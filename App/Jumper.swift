// Brings the user to an agent session: the exact tab in Terminal/iTerm2 (matched by tty),
// otherwise the app hosting the agent (Claude, Codex, VS Code, Ghostty, …).
import AppKit

@MainActor
enum Jumper {
    static func open(_ s: AgentSession) {
        guard let pid = s.pid else { return }
        guard let app = hostApp(pid) else { return }
        if let tty = Proc.tty(pid), selectTab(in: app, tty: tty) { return }
        bringToFront(app)
    }

    /// `NSRunningApplication.activate()` is ignored for a background app on macOS 14+ (cooperative activation),
    /// so "re-open" the app through Launch Services instead, the same way Finder does.
    static func bringToFront(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error { NSLog("AgentMonitor: can't activate \(url.lastPathComponent): \(error)") }
        }
    }

    static func hostApp(_ pid: pid_t) -> NSRunningApplication? {
        for p in Proc.ancestors(pid) {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
        }
        return nil
    }

    private static func selectTab(in app: NSRunningApplication, tty: String) -> Bool {
        let script: String
        switch app.bundleIdentifier {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      tell t to select
                      tell s to select
                      activate
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default:
            return false
        }
        var err: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&err)
        return err == nil && result?.booleanValue == true
    }
}
