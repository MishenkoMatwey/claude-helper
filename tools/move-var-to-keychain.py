#!/usr/bin/env python3
"""
Move a plain variable from <agent>/vars.json into macOS Keychain.

Mirrors AgentVariablesService.swift:
- projectId = DJB2 hash of project root path, truncated base36(10).
- service   = claude-agent-<projectId>-<agentName>
- account   = <KEY>

Usage:
  python3 move-var-to-keychain.py <agent-memory-dir> <KEY>

Example:
  python3 move-var-to-keychain.py \\
    /Users/.../clussters/.claude/agents/memory/gitlab TOKEN

The script never prints the value. On success, it prints only the service id.
"""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path


def djb2_base36(s: str, length: int = 10) -> str:
    h = 5381
    mask = (1 << 64) - 1
    for byte in s.encode("utf-8"):
        h = ((h << 5) + h + byte) & mask
    if h == 0:
        return "0"
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = ""
    while h:
        h, r = divmod(h, 36)
        out = chars[r] + out
    return out[:length]


def project_root_from_memory_dir(agent_dir: Path) -> Path:
    """memory/<agent>/ → project root by walking up to `.claude/`."""
    p = agent_dir.resolve()
    for parent in p.parents:
        if parent.name == ".claude":
            return parent.parent
    raise SystemExit(f"cannot derive project root from {agent_dir}")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    agent_dir = Path(sys.argv[1])
    key = sys.argv[2]
    if not agent_dir.is_dir():
        print(f"not a directory: {agent_dir}", file=sys.stderr)
        return 2

    agent_name = agent_dir.name
    vars_path = agent_dir / "vars.json"
    if not vars_path.exists():
        print(f"no vars.json in {agent_dir}", file=sys.stderr)
        return 2

    project_root = project_root_from_memory_dir(agent_dir)
    is_global = project_root == Path.home()
    project_id = "user" if is_global else djb2_base36(str(project_root))
    service = f"claude-agent-{project_id}-{agent_name}"

    with open(vars_path) as f:
        data = json.load(f)
    if key not in data:
        print(f"key '{key}' not in vars.json", file=sys.stderr)
        return 2
    value = data[key]
    if not isinstance(value, str) or not value:
        print(f"value for '{key}' is empty / not a string", file=sys.stderr)
        return 2

    # Write to Keychain (-U: update if exists)
    res = subprocess.run(
        ["security", "add-generic-password", "-s", service, "-a", key, "-w", value, "-U"],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        print(f"security failed: {res.stderr.strip()}", file=sys.stderr)
        return res.returncode

    # Sanity check — read it back, compare without printing
    verify = subprocess.run(
        ["security", "find-generic-password", "-s", service, "-a", key, "-w"],
        capture_output=True,
        text=True,
    )
    if verify.returncode != 0 or verify.stdout.strip() != value:
        print("verification failed — value not readable from Keychain", file=sys.stderr)
        return 3

    # Remove from vars.json
    del data[key]
    if data:
        vars_path.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    else:
        vars_path.write_text("{}\n")

    print(f"✓ moved '{key}' from {vars_path.name} to Keychain (service={service})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
