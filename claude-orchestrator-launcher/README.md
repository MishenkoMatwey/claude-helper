# Claude Orchestrator Launcher (IntelliJ plugin)

Minimal IntelliJ IDEA plugin: one action that opens IDE's built-in Terminal and runs `claude --agent orchestrator --add-dir <project>`.

## Build

```bash
cd /Users/MishchenkoMatwey/Desktop/claude-orchestrator-launcher
./gradlew buildPlugin
```

Plugin ZIP appears in `build/distributions/claude-orchestrator-launcher-0.1.0.zip`.

## Install in IDEA

1. **Settings → Plugins** → ⚙ (gear icon) → **Install Plugin from Disk…**
2. Pick `build/distributions/claude-orchestrator-launcher-0.1.0.zip`.
3. Restart IDEA.

## Use

- **Tools → Start Claude Orchestrator** — opens dialog with single option `orchestrator`, click OK.
- A new Terminal tab opens labelled `Claude: orchestrator`, executes
  `claude --agent orchestrator --add-dir <projectPath>`.
- Keyboard shortcut: **Ctrl+Shift+O** (re-bind in Keymap if conflicts).

## Adding more agents

In `StartOrchestratorAction.kt` change:
```kotlin
val agents = arrayOf("orchestrator")
```
to e.g.
```kotlin
val agents = arrayOf("orchestrator", "developer-BE", "reviewer-BE", "mr-reviewer")
```
Rebuild the plugin.

## Requirements

- IntelliJ IDEA 2024.1+ (build 241+, supports up to 251.*)
- `claude` CLI installed in PATH (`/Users/MishchenkoMatwey/.local/bin/claude`)
- JDK 17 for building
