<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Agent Monitor icon">
</p>

<h1 align="center">Agent Monitor</h1>

<p align="center">
  A native macOS desktop widget for your <b>Claude Code</b> and <b>Codex</b> usage limits.<br>
  5-hour window and weekly window, at a glance, right on your desktop.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-F05138?logo=swift&logoColor=white">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center">
  <img src="docs/hero.png" alt="Agent Monitor widgets in dark and light mode" width="760">
</p>

---

## Why

Claude Code and Codex both meter you on two windows: a rolling **5-hour** limit and a **weekly** one. Hitting either mid-task is annoying, and checking means running a slash command or opening a settings page. Agent Monitor puts both numbers for both agents on your desktop, as a real macOS widget.

## Features

- **Real WidgetKit widget.** It lives in the widget gallery and snaps to the desktop grid like Weather or Calendar.
- **Two sizes.** Medium shows four rings, small shows compact bars.
- **Countdowns.** Time until each window resets, updated every minute.
- **Color warnings.** Each ring turns amber at 75% and red at 90%.
- **Light and dark.** Follows the system appearance.
- **Menu bar companion.** Shows the current numbers and offers *Refresh*, *Launch at Login* and *Quit*.
- **Zero config.** Reuses the logins you already have in Claude Code and Codex CLI.

## Install

**Requirements:** macOS 14 Sonoma or later, Xcode 15 or later (free from the App Store), and Claude Code and/or Codex CLI signed in on this Mac.

> Xcode is needed because WidgetKit extensions can't be built with the Command Line Tools alone. You don't need an Apple Developer account: the app is signed locally ("Sign to Run Locally").

```bash
git clone https://github.com/paveler/agent-monitor.git
cd agent-monitor
./scripts/install.sh
```

The script builds the app, copies it to `/Applications` and launches it. You'll see a gauge icon in the menu bar.

Then:

1. **Add the widget.** Right-click the desktop → **Edit Widgets…** → search **Agent Monitor** → drag the medium or small widget onto the desktop.
2. **Allow Keychain access.** On first launch macOS asks to let Agent Monitor read `Claude Code-credentials`. Click **Always Allow**.
3. **Turn on Launch at Login** in the menu bar icon. The widget shows data the app collects, so keep the app running.

### Updating

```bash
git pull && ./scripts/install.sh
```

### Uninstalling

Quit from the menu bar icon, remove the widget from the desktop, then:

```bash
rm -rf /Applications/AgentMonitor.app ~/Library/Application\ Support/AgentMonitor
```

## How it works

```
┌──────────────────────┐   every 2 min   ┌──────────────────────────────┐
│  Menu bar app        │ ──────────────▶ │ ~/Library/Application Support│
│  (not sandboxed)     │   snapshot.json │   /AgentMonitor/             │
│                      │                 └──────────────┬───────────────┘
│  • Claude: Keychain  │                                │ read-only
│    → Anthropic API   │   reloadTimelines              ▼
│  • Codex: ~/.codex   │ ──────────────▶  ┌──────────────────────────┐
│    → ChatGPT API     │                  │ WidgetKit extension      │
│    (fallback: logs)  │                  │ (sandboxed)              │
└──────────────────────┘                  └──────────────────────────┘
```

| Agent  | Where the credentials come from                         | Where the usage comes from |
|--------|---------------------------------------------------------|----------------------------|
| Claude | Claude Code's OAuth token in the macOS Keychain          | `api.anthropic.com/api/oauth/usage` |
| Codex  | Codex CLI's token in `~/.codex/auth.json`                | `chatgpt.com/backend-api/wham/usage`, falling back to the latest `rate_limits` event in `~/.codex/sessions` |

Widgets are sandboxed and can't read the Keychain or `~/.codex`. So a small menu bar app does the fetching, writes a JSON snapshot, and the widget only has read access to that one folder.

## Privacy

- Your tokens never leave your Mac, except to the same Anthropic and OpenAI endpoints the official CLIs already talk to.
- There's no analytics, no telemetry and no third-party servers.
- The snapshot file contains only percentages and reset times.

## Caveats

- **Both usage endpoints are undocumented.** They're what the official tools use internally, and they can change without notice. If a number disappears after an update, please open an issue.
- **Claude tokens expire.** Claude Code refreshes its token when you use it. If the widget says *Token expired*, open Claude Code once.
- **The Codex fallback can be stale.** When the API isn't reachable, the numbers come from your last Codex session. A window that has already reset is shown as 0%.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Widget says **No data yet** | Click the menu bar icon: do numbers show there? If yes, remove the widget and add it again (macOS caches old builds). |
| **Not signed in to Claude Code** | Run `claude` and log in, then click **Refresh**. |
| No Keychain prompt and no Claude data | Open **Keychain Access**, find `Claude Code-credentials`, and allow Agent Monitor under **Access Control**. |
| Widget doesn't appear in the gallery | Make sure the app is in `/Applications` and has been launched once. Then log out and back in. |
| Build fails with *requires Xcode* | Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. |

## Development

```
App/      menu bar app: fetching, snapshot, menu
Widget/   WidgetKit extension: timeline provider and SwiftUI views
Shared/   model, snapshot store, app icon assets
tools/    icon generator and README preview renderer
```

- The project is described in [`project.yml`](project.yml) ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). The generated `AgentMonitor.xcodeproj` is committed, so XcodeGen is optional.
- Regenerate the icon: `swift tools/make_icon.swift icon.png`.
- Re-render the README image from the real widget views: `tools/render-previews.sh`.

PRs welcome. Ideas on the list: notifications near the limit, usage history sparkline, and more agents (Gemini CLI, Cursor).

## License

[MIT](LICENSE). Not affiliated with Anthropic or OpenAI. Claude and Codex are trademarks of their respective owners.
