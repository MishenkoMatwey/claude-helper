# Claude Agents Monitor

Native macOS menu bar app for managing Claude Code subagents, workflows, and schedules.

## Features

- **Menu bar widget** — always-visible 5-hour + weekly usage, active sessions, sparkline of 14-day usage. Real numbers from Claude Code's `/api/oauth/usage` endpoint, not estimates.
- **Per-project agents** — create, edit, delete agents stored in `<project>/.claude/agents/`. Permissions, skills, MCP servers, secrets per agent.
- **Visual BPMN workflow editor** — drag-and-drop nodes, conditional branches, auto-layout, validation, live execution via the orchestrator agent.
- **Schedules** — cron, one-time, or "on rate-limit reset" triggers. Local backend or copy a Claude routine command for cloud scheduling.
- **Plugin browser** — 177+ Claude Code plugins from the official marketplace, one-click enable.
- **Playbook mining** — extract reusable procedures from past Claude Code sessions via headless `claude -p` calls.
- **Memory layers** — global SHARED.md + per-agent private journal + structured playbooks. Auto-injected protocol so agents read/write on every task.
- **Rate-limit auto-resume** — when a workflow hits a 5-hour or weekly limit, it registers a paused execution. When the limit resets, `claude --resume <session>` continues automatically.

## Architecture

Feature-first SwiftUI + DI:

```
Sources/ClaudeAgentsMonitor/
├── App/               # AppState (thin coordinator) + entry point
├── Core/              # DesignSystem, DI container, formatters
├── Infrastructure/    # ClaudeAPI, MCP, Notifications, Tokens, AgentPaths
└── Features/
    ├── Agents/        # Model · ViewModel · Service · View
    ├── Workflows/
    ├── Schedules/
    ├── Projects/
    ├── Plugins/
    ├── Skills/
    ├── Dashboard/
    ├── MenuBar/
    └── Orchestrator/
```

Every service is exposed via a protocol (`*Repository`, `*Client`) and wired through a single `AppContainer`. Views consume feature `ViewModel`s rather than reaching into infrastructure directly.

## Requirements

- macOS 14 Sonoma+
- Swift 6 (ships with Xcode 16 or Command Line Tools 16+)
- Claude Code installed and authenticated (`claude` CLI in `~/.local/bin` or `/opt/homebrew/bin`)

## Build & run

```sh
swift build
./build-app.sh
open dist/ClaudeAgentsMonitor.app
```

`build-app.sh` produces a proper `.app` bundle with `LSUIElement=YES` (menu bar only, no Dock icon) and the generated `AppIcon.icns`.

## Tests

Tests live in `Tests/ClaudeAgentsMonitorTests/` using Swift Testing (`import Testing`). They require **full Xcode** (not just Command Line Tools) because `swift-testing` depends on C++ stdlib. To enable:

1. Install Xcode from the App Store
2. Uncomment the `.testTarget` in `Package.swift`
3. `swift test`

## License

Personal project — no license set yet.
