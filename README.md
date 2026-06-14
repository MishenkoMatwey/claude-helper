# Claude Agents Monitor

Native macOS menu bar app for managing Claude Code subagents, workflows, and schedules.

## Features

- **Menu bar widget** — always-visible 5-hour + weekly usage, active sessions, sparkline of 14-day usage. Real numbers from Claude Code's `/api/oauth/usage` endpoint, not estimates.
- **Per-project agents** — create, edit, delete agents stored in `<project>/.claude/agents/`. Permissions, skills, MCP servers, secrets per agent.
- **Agent memory (v3)** — SQLite-backed notes (facts/rules/playbooks/sessions/vars) with links (graph) and FTS search. Exposed to agents through the `cam-memory` MCP server (`memory_search` / `memory_write` / `memory_link`) so they recall instead of re-reading. Searchable list + graph view in the UI.
- **Resumable agent sessions** — the orchestrator delegates via the `cam-agents` MCP server (`agent_run` / `agent_continue`): follow-up edits resume the *same* `claude` session, keeping project context loaded (no cold re-read). Background runs (`agent_run background:true`) with `agent_status` / `agent_stop`, monitored and stoppable from the "Running agents" panel.
- **Plugin browser** — 177+ Claude Code plugins from the official marketplace, one-click enable.
- **Rate-limit auto-resume** — when a run hits a 5-hour or weekly limit, it registers a paused execution; when the limit resets, `claude --resume <session>` continues automatically.

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

`swift test` requires **full Xcode** (not just Command Line Tools) — `XCTest` / `swift-testing` don't ship with the CLT toolchain. Swift Testing suites live in `Tests/ClaudeAgentsMonitorTests/`; to run them, install Xcode, uncomment the `.testTarget` in `Package.swift`, then `swift test`.

For the common Command-Line-Tools-only setup, a runnable self-test harness covers the core services (memory store, v2→v3 migration, agent-run store/runner, agent wiring) with no GUI or network:

```sh
swift build && .build/debug/ClaudeAgentsMonitor --selftest
```

### Maintenance / headless commands

The same binary doubles as the MCP servers and maintenance CLI (it exits before the GUI):

| Flag | What it does |
|------|--------------|
| `--mcp-serve --db <db> --agent <name>` | `cam-memory` MCP server (per agent) |
| `--agents-serve --project <root>` | `cam-agents` MCP server (resumable/background runs) |
| `--migrate-all [--project <root>]` | migrate v2 file memory → v3 SQLite |
| `--rewire-all [--project <root>]` | regenerate agents onto the v3 memory stack |
| `--rewire-orchestrators [--project <root>]` | rebuild orchestrators with resumable-session tools |
| `--selftest` | run the self-test harness |

## Subprojects

- [`claude-orchestrator-launcher/`](claude-orchestrator-launcher/) — standalone IntelliJ/JetBrains plugin (Kotlin + Gradle): **Tools → Start Claude Orchestrator** (Ctrl+Shift+O), discovers orchestrators by `.claude/agents/`. Independent build (`./gradlew`), its own `.gitignore`.

## License

Personal project — no license set yet.
