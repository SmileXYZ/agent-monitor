// Agent Monitor: a background menu bar app.
// • Fetches Claude/Codex usage limits and writes a snapshot for the widget.
// • Watches session files written by agent hooks and shows who's waiting on you, in real time.
// • `AgentMonitor --hook <agent>` runs as a hook handler and exits (see Hook.swift).
import AppKit
import ServiceManagement
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var snapshot = SharedStore.load() ?? Snapshot()
    private var waiting: [AgentSession] = []
    private var loading = false
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                           accessibilityDescription: "Agent Monitor")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in self.refresh(); self.reloadSessions() }
        }

        startWatching()
        reloadSessions()
        // Ages tick and dead sessions get swept even when no hook fires.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.reloadSessions() }
        }
    }

    // MARK: usage limits

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            async let c = ClaudeSource.fetch()
            async let x = CodexSource.fetch()
            let (cc, xx) = await (c, x)
            snapshot = Snapshot(claude: cc, codex: xx, updated: Date())
            SharedStore.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "AgentMonitorWidget")
            loading = false
        }
    }

    // MARK: sessions

    private func startWatching() {
        guard let dir = SessionStore.sessionsDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            // Debounce bursts of hook writes.
            guard let self, !self.reloadPending else { return }
            self.reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reloadPending = false
                self.reloadSessions()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    func reloadSessions() {
        var all = SessionStore.loadAll()
        // Sweep sessions whose agent process is gone (SessionEnd isn't guaranteed, e.g. closed terminal).
        all.removeAll { s in
            if let pid = s.pid, !Proc.isAlive(pid) { SessionStore.remove(s.id); return true }
            return false
        }
        let now = Date()
        let next = SessionStore.visible(all, now: now)
        updateStatusTitle(next)
        if next != waiting {
            waiting = next
            SessionStore.saveWaiting(next)
            WidgetCenter.shared.reloadTimelines(ofKind: "WaitingWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "AgentMonitorWidget")   // large size shows the list too
        }
    }

    private func updateStatusTitle(_ list: [AgentSession]) {
        guard let button = statusItem.button else { return }
        if list.isEmpty { button.attributedTitle = NSAttributedString(string: ""); return }
        let blocking = list.contains { $0.state.isBlocking }
        let color: NSColor = blocking ? .systemRed : .labelColor
        button.attributedTitle = NSAttributedString(
            string: " \(list.count)",
            attributes: [.foregroundColor: color, .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)])
    }

    @objc private func jump(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? AgentSession { Jumper.open(s) }
    }

    /// Widget taps arrive as agentmonitor://session/<id>.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "agentmonitor" && url.host == "session" {
            let id = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            if let s = SessionStore.load(id) ?? waiting.first(where: { $0.id == id }) { Jumper.open(s) }
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()

        func header(_ title: String) {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }

        header(waiting.isEmpty ? "Nothing is waiting on you" : "Waiting on you")
        for s in waiting {
            let it = NSMenuItem(title: "", action: #selector(jump(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s
            let stateColor: NSColor = s.state.isBlocking ? .systemRed : .secondaryLabelColor
            let t = NSMutableAttributedString(string: "\(s.displayTitle)  ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
            t.append(NSAttributedString(string: s.state.label, attributes: [.foregroundColor: stateColor]))
            let meta = s.displayTitle == s.project ? "" : "\(s.project) · "
            t.append(NSAttributedString(string: "  ·  \(meta)\(s.agentName) · \(ago(s.since, now: now))",
                                        attributes: [.foregroundColor: NSColor.tertiaryLabelColor]))
            if let d = s.detail {
                t.append(NSAttributedString(string: "\n\(d)", attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 11)]))
            }
            it.attributedTitle = t
            it.toolTip = s.cwd
            menu.addItem(it)
        }

        menu.addItem(.separator())
        func line(_ name: String, _ u: AgentUsage) -> String {
            if let e = u.error { return "\(name): \(e)" }
            func p(_ l: Limit) -> String { l.effectivePercent().map { "\(Int($0.rounded()))%" } ?? "—" }
            return "\(name):  5h \(p(u.fiveHour))  ·  week \(p(u.week))"
        }
        header(line("Claude", snapshot.claude))
        header(line("Codex", snapshot.codex))
        if let u = snapshot.updated { header("Updated " + u.formatted(date: .omitted, time: .shortened)) }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshAction), keyEquivalent: "r").target = self

        let integrations = NSMenuItem(title: "Integrations", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for t in [HookInstaller.claude, HookInstaller.codex] {
            let on = HookInstaller.isInstalled(t)
            let it = NSMenuItem(title: on ? "\(t.name) hooks connected" : "Connect \(t.name)…",
                                action: #selector(toggleHooks(_:)), keyEquivalent: "")
            it.target = self
            it.state = on ? .on : .off
            it.representedObject = t.agent
            sub.addItem(it)
        }
        integrations.submenu = sub
        menu.addItem(integrations)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func refreshAction() { refresh(); reloadSessions() }

    @objc private func toggleHooks(_ sender: NSMenuItem) {
        let t = (sender.representedObject as? String) == "codex" ? HookInstaller.codex : HookInstaller.claude
        let installed = HookInstaller.isInstalled(t)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        if installed {
            alert.messageText = "Disconnect \(t.name)?"
            alert.informativeText = "Agent Monitor's hooks will be removed from \(t.path.path). Your other hooks stay untouched."
            alert.addButton(withTitle: "Disconnect")
        } else {
            alert.messageText = "Connect \(t.name)?"
            var info = "Agent Monitor will add hooks to \(t.path.path) so it can tell when \(t.name) is waiting for you. "
                + "Existing hooks are kept, and a backup is saved next to the file (.agentmonitor-backup)."
            if t.agent == "codex" {
                info += "\n\nCodex asks you to trust new hooks: run /hooks in Codex CLI, or open Settings → Hooks in the Codex app."
            } else {
                info += "\n\nApplies to new Claude Code sessions (restart running ones)."
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Connect")
        }
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if installed { try HookInstaller.uninstall(t) } else { try HookInstaller.install(t) }
        } catch {
            let e = NSAlert(error: error)
            e.runModal()
        }
    }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            NSLog("login item: \(error)")
        }
    }
}

// Hook mode: handle one event and exit before any UI starts.
if let i = CommandLine.arguments.firstIndex(of: "--hook") {
    let agent = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "claude"
    Hook.run(agent: agent)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
