// Agent Monitor: a background menu bar app.
// Fetches Claude/Codex limits, writes a snapshot and reloads the widget.
import AppKit
import ServiceManagement
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var snapshot = SharedStore.load() ?? Snapshot()
    private var loading = false

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                           accessibilityDescription: "Agent Monitor")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
        // Refresh right after wake.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            async let c = ClaudeSource.fetch()
            async let x = CodexSource.fetch()
            let (cc, xx) = await (c, x)
            snapshot = Snapshot(claude: cc, codex: xx, updated: Date())
            SharedStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            loading = false
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func line(_ name: String, _ u: AgentUsage) -> String {
            if let e = u.error { return "\(name): \(e)" }
            func p(_ l: Limit) -> String { l.effectivePercent().map { "\(Int($0.rounded()))%" } ?? "—" }
            return "\(name):  5h \(p(u.fiveHour))  ·  week \(p(u.week))"
        }
        for s in [line("Claude", snapshot.claude), line("Codex", snapshot.codex)] {
            let it = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }
        if let u = snapshot.updated {
            let it = NSMenuItem(title: "Updated " + u.formatted(date: .omitted, time: .shortened),
                                action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshAction), keyEquivalent: "r").target = self
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func refreshAction() { refresh() }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            NSLog("login item: \(error)")
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
