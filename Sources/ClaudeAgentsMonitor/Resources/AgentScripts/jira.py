#!/usr/bin/env python3
"""jira.py — reference CLI for the Jira template agent.

Encapsulates the Atlassian REST patterns so the agent calls a tested command
instead of hand-rolling curl + jq every task (cheaper, faster, no escaping or
/search-vs-/search-jql footguns).

Auth & config come from the environment (nothing secret is ever printed):
    JIRA_API_TOKEN   required — Atlassian API token
    JIRA_EMAIL       required — account email (Basic auth user)
    JIRA_BASE_URL    default https://clussters.atlassian.net
Project defaults (override via env if reused elsewhere):
    JIRA_PROJECT     default CLS
    JIRA_TEAM_FIELD  default customfield_10001     (Team)
    JIRA_TEAM_WASABI default ec5ed31d-8f13-48ed-b805-e89a183cf067
    JIRA_TEAM_BBQ    default b1f4a2fd-71f6-40d9-95ee-7ac3e4ef529c

Stdlib only — runs as `python3 jira.py <cmd>` with no pip install.

Examples:
    python3 jira.py me
    python3 jira.py my-tasks
    python3 jira.py tasks "Иван"
    python3 jira.py ticket CLS-3396
    python3 jira.py sprint
    python3 jira.py sprint --stats
    python3 jira.py epics --team wasabi
    python3 jira.py boards
    python3 jira.py search "project = CLS AND statusCategory != Done" --max 20
    python3 jira.py create --type Bug --summary "Login 500" --team wasabi --assignee <accountId> --sprint active
Add --json to any command for raw machine-readable output.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter

# --- config (env overridable) ------------------------------------------------

def _email_from_jira_cli() -> str:
    """Fallback: read `login:` from the jira-cli config so agents need only the token."""
    cfg = os.path.expanduser("~/.config/.jira/.config.yml")
    try:
        with open(cfg, encoding="utf-8") as fh:
            for line in fh:
                if line.strip().startswith("login:"):
                    return line.split(":", 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return ""


BASE = os.environ.get("JIRA_BASE_URL", "https://clussters.atlassian.net").rstrip("/")
EMAIL = os.environ.get("JIRA_EMAIL", "") or _email_from_jira_cli()
TOKEN = os.environ.get("JIRA_API_TOKEN", "")
PROJECT = os.environ.get("JIRA_PROJECT", "CLS")
TEAM_FIELD = os.environ.get("JIRA_TEAM_FIELD", "customfield_10001")
TEAMS = {
    "wasabi": os.environ.get("JIRA_TEAM_WASABI", "ec5ed31d-8f13-48ed-b805-e89a183cf067"),
    "bbq": os.environ.get("JIRA_TEAM_BBQ", "b1f4a2fd-71f6-40d9-95ee-7ac3e4ef529c"),
}
DEFAULT_FIELDS = ["summary", "status", "assignee", "priority", "issuetype"]


def die(msg: str, code: int = 1) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


# --- HTTP --------------------------------------------------------------------

def _request(method: str, path: str, params: dict | None = None, body: dict | None = None) -> dict:
    if not TOKEN:
        die("JIRA_API_TOKEN is not set")
    if not EMAIL:
        die("JIRA_EMAIL is not set")
    url = f"{BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    auth = base64.b64encode(f"{EMAIL}:{TOKEN}".encode()).decode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Basic {auth}")
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        die(f"HTTP {e.code} on {method} {path}: {detail}", code=2)
    except urllib.error.URLError as e:
        die(f"network error on {path}: {e.reason}", code=2)


def get(path, params=None):
    return _request("GET", path, params=params)


def post(path, body):
    return _request("POST", path, body=body)


def search_jql(jql: str, fields=None, max_results: int = 50) -> list[dict]:
    """Enhanced search (/rest/api/3/search/jql) with nextPageToken paging."""
    fields = fields or DEFAULT_FIELDS
    issues: list[dict] = []
    token = None
    while len(issues) < max_results:
        params = {"jql": jql, "maxResults": min(100, max_results - len(issues)),
                  "fields": ",".join(fields)}
        if token:
            params["nextPageToken"] = token
        data = get("/rest/api/3/search/jql", params)
        issues.extend(data.get("issues", []))
        token = data.get("nextPageToken")
        if data.get("isLast", True) or not token:
            break
    return issues[:max_results]


# --- formatting --------------------------------------------------------------

def _field(issue: dict, name: str) -> str:
    f = issue.get("fields", {})
    v = f.get(name)
    if v is None:
        return "—"
    if isinstance(v, dict):
        return v.get("name") or v.get("displayName") or v.get("value") or "—"
    return str(v)


def issue_rows(issues: list[dict]) -> list[list[str]]:
    rows = []
    for it in issues:
        rows.append([
            _field(it, "issuetype"),
            it.get("key", "—"),
            _field(it, "summary")[:70],
            _field(it, "status"),
            _field(it, "assignee"),
            _field(it, "priority"),
        ])
    return rows


def table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return "(пусто)"
    widths = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(str(c)))
    line = lambda cells: " | ".join(str(c).ljust(widths[i]) for i, c in enumerate(cells))
    sep = "-+-".join("-" * w for w in widths)
    return "\n".join([line(headers), sep, *[line(r) for r in rows]])


def emit(args, payload, headers=None, rows=None):
    """Print JSON if --json, else a human table/text."""
    if getattr(args, "json", False):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif rows is not None:
        print(table(headers, rows))
    else:
        print(payload)


# --- helpers -----------------------------------------------------------------

def resolve_account_id(name: str) -> str:
    users = get("/rest/api/3/user/search", {"query": name})
    if not users:
        die(f"no user matches '{name}'")
    return users[0]["accountId"]


def active_sprint_id() -> int | None:
    # Look across the project's boards for an active sprint.
    boards = get("/rest/agile/1.0/board", {"projectKeyOrId": PROJECT}).get("values", [])
    for b in boards:
        sprints = get(f"/rest/agile/1.0/board/{b['id']}/sprint", {"state": "active"}).get("values", [])
        if sprints:
            return sprints[0]["id"]
    return None


# --- commands ----------------------------------------------------------------

def cmd_me(args):
    me = get("/rest/api/3/myself")
    emit(args, me, ["Field", "Value"],
         [["displayName", me.get("displayName", "—")],
          ["accountId", me.get("accountId", "—")],
          ["email", me.get("emailAddress", "—")]])


def _list_issues(args, jql, fields=None):
    issues = search_jql(jql, fields=fields, max_results=args.max)
    emit(args, issues, ["TYPE", "KEY", "SUMMARY", "STATUS", "ASSIGNEE", "PRIORITY"], issue_rows(issues))


def cmd_my_tasks(args):
    _list_issues(args, "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC")


def cmd_tasks(args):
    aid = resolve_account_id(args.name)
    _list_issues(args, f"assignee = {aid} AND statusCategory != Done ORDER BY priority DESC")


def cmd_ticket(args):
    issue = get(f"/rest/api/3/issue/{args.key}",
                {"fields": "summary,status,assignee,priority,issuetype,description,labels"})
    if args.json:
        print(json.dumps(issue, ensure_ascii=False, indent=2))
        return
    f = issue.get("fields", {})
    print(f"{issue.get('key')}  [{_field(issue,'issuetype')}]  {_field(issue,'status')}")
    print(f"Summary : {_field(issue,'summary')}")
    print(f"Assignee: {_field(issue,'assignee')}    Priority: {_field(issue,'priority')}")
    print(f"Link    : {BASE}/browse/{issue.get('key')}")


def cmd_sprint(args):
    jql = f"sprint in openSprints() AND project = {PROJECT} ORDER BY status ASC, priority DESC"
    # Stats must count the whole sprint, not just the default page.
    max_results = max(args.max, 500) if args.stats else args.max
    issues = search_jql(jql, max_results=max_results)
    if args.stats:
        return _sprint_stats(args, issues)
    emit(args, issues, ["TYPE", "KEY", "SUMMARY", "STATUS", "ASSIGNEE", "PRIORITY"], issue_rows(issues))


def _sprint_stats(args, issues):
    by_status = Counter(_field(i, "status") for i in issues)
    by_type = Counter(_field(i, "issuetype") for i in issues)
    by_assignee = Counter(_field(i, "assignee") for i in issues)
    if args.json:
        print(json.dumps({"total": len(issues), "by_status": by_status,
                          "by_type": by_type, "by_assignee": by_assignee},
                         ensure_ascii=False, indent=2))
        return
    print(f"Спринт: {len(issues)} задач\n")
    for title, c in [("По статусам", by_status), ("По типам", by_type), ("По исполнителям", by_assignee)]:
        print(f"## {title}")
        print(table(["Значение", "Кол-во"], [[k, str(v)] for k, v in c.most_common()]))
        print()


def cmd_epics(args):
    jql = f"project = {PROJECT} AND issuetype = Epic AND status not in (Cancelled)"
    if args.team:
        jql += f' AND cf[{TEAM_FIELD[12:]}] = "{TEAMS[args.team]}"'
    jql += " ORDER BY status ASC, created DESC"
    _list_issues(args, jql, fields=["summary", "status", "assignee", "issuetype"])


def cmd_backlog(args):
    jql = f"project = {PROJECT} AND sprint is EMPTY AND statusCategory != Done"
    if args.team:
        jql += f' AND cf[{TEAM_FIELD[12:]}] = "{TEAMS[args.team]}"'
    jql += " ORDER BY priority DESC, created DESC"
    _list_issues(args, jql)


def cmd_boards(args):
    boards = get("/rest/agile/1.0/board", {"projectKeyOrId": PROJECT}).get("values", [])
    emit(args, boards, ["ID", "NAME", "TYPE"],
         [[str(b["id"]), b.get("name", "—"), b.get("type", "—")] for b in boards])


def cmd_search(args):
    _list_issues(args, args.jql)


def cmd_release_notes(args):
    if args.jql:
        jql = args.jql
    elif args.version:
        jql = f'project = {PROJECT} AND fixVersion = "{args.version}"'
        if args.team:
            jql += f' AND cf[{TEAM_FIELD[12:]}] = "{TEAMS[args.team]}"'
    else:
        die('release-notes needs --version <fixVersion> or --jql "<JQL>"')
    jql += " ORDER BY issuetype ASC, key ASC"
    issues = search_jql(jql, fields=["summary", "issuetype", "status"], max_results=max(args.max, 500))
    if args.json:
        print(json.dumps(issues, ensure_ascii=False, indent=2))
        return
    print(f"# {args.version or 'Release notes'}\n")
    groups: dict[str, list[dict]] = {}
    for it in issues:
        groups.setdefault(_field(it, "issuetype"), []).append(it)
    for kind in sorted(groups):
        print(f"## {kind} ({len(groups[kind])})")
        for it in groups[kind]:
            key = it.get("key")
            print(f"- [{key}]({BASE}/browse/{key}) — {_field(it, 'summary')}")
        print()


def cmd_transition(args):
    """Move one or many issues to a target status — loops in-script (fast, no
    per-issue LLM round trips). For each key: find the transition whose target
    status matches `--to`, then POST it."""
    target = args.to.strip().lower()
    results = []
    for key in args.keys:
        try:
            data = get(f"/rest/api/3/issue/{key}/transitions")
            trans = data.get("transitions", [])
            match = next((t for t in trans
                          if (t.get("to", {}).get("name", "").lower() == target
                              or t.get("name", "").lower() == target)), None)
            if not match:
                avail = ", ".join(t.get("to", {}).get("name", t.get("name", "?")) for t in trans)
                results.append((key, "skip", f"нет перехода в '{args.to}' (есть: {avail})"))
                continue
            post(f"/rest/api/3/issue/{key}/transitions", {"transition": {"id": match["id"]}})
            results.append((key, "ok", args.to))
        except SystemExit:
            results.append((key, "fail", "HTTP error"))
    if args.json:
        print(json.dumps([{"key": k, "status": s, "detail": d} for k, s, d in results],
                         ensure_ascii=False, indent=2))
        return
    ok = sum(1 for _, s, _ in results if s == "ok")
    print(f"Переведено в '{args.to}': {ok}/{len(results)}")
    for k, s, d in results:
        mark = {"ok": "✓", "skip": "—", "fail": "✗"}.get(s, "?")
        print(f"  {mark} {k}: {d}")


def cmd_create(args):
    fields: dict = {
        "project": {"key": PROJECT},
        "issuetype": {"name": args.type},
        "summary": args.summary,
    }
    if args.desc:
        fields["description"] = {
            "type": "doc", "version": 1,
            "content": [{"type": "paragraph", "content": [{"type": "text", "text": args.desc}]}],
        }
    if args.team:
        fields[TEAM_FIELD] = TEAMS[args.team]
    if args.assignee:
        fields["assignee"] = {"accountId": args.assignee}
    created = post("/rest/api/3/issue", {"fields": fields})
    key = created.get("key")
    if not key:
        die(f"create failed: {json.dumps(created, ensure_ascii=False)}")

    sprint_msg = ""
    if args.sprint == "active":
        sid = active_sprint_id()
        if sid:
            post(f"/rest/agile/1.0/sprint/{sid}/issue", {"issues": [key]})
            sprint_msg = f" (добавлено в спринт {sid})"
    if args.json:
        print(json.dumps({"key": key, "url": f"{BASE}/browse/{key}", "sprint": args.sprint}, ensure_ascii=False))
    else:
        print(f"✓ {args.type} создан: {key}{sprint_msg}\n  {BASE}/browse/{key}")


# --- argparse ----------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    # Common flags available in either position (before or after the subcommand).
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="raw JSON output")
    common.add_argument("--max", type=int, default=50, help="max issues to fetch (default 50)")

    p = argparse.ArgumentParser(prog="jira.py", description="Jira agent CLI (stdlib only)",
                                parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)

    def add(name, help):  # every subcommand inherits the common flags
        return sub.add_parser(name, help=help, parents=[common])

    add("me", "verify auth / show current user").set_defaults(fn=cmd_me)
    add("my-tasks", "my open tasks").set_defaults(fn=cmd_my_tasks)

    sp = add("tasks", "open tasks of a person"); sp.add_argument("name"); sp.set_defaults(fn=cmd_tasks)
    sp = add("ticket", "issue details"); sp.add_argument("key"); sp.set_defaults(fn=cmd_ticket)

    sp = add("sprint", "current sprint (add --stats for summary)")
    sp.add_argument("--stats", action="store_true"); sp.set_defaults(fn=cmd_sprint)

    sp = add("epics", "epics (optionally per team)")
    sp.add_argument("--team", choices=list(TEAMS)); sp.set_defaults(fn=cmd_epics)

    sp = add("backlog", "items outside any sprint")
    sp.add_argument("--team", choices=list(TEAMS)); sp.set_defaults(fn=cmd_backlog)

    add("boards", "project boards").set_defaults(fn=cmd_boards)

    sp = add("search", "raw JQL escape hatch"); sp.add_argument("jql"); sp.set_defaults(fn=cmd_search)

    sp = add("release-notes", "markdown release notes for a fixVersion (grouped by type)")
    sp.add_argument("--version", help="fixVersion name")
    sp.add_argument("--team", choices=list(TEAMS))
    sp.add_argument("--jql", help="custom JQL instead of --version")
    sp.set_defaults(fn=cmd_release_notes)

    sp = add("transition", "move one or many issues to a status (batch)")
    sp.add_argument("--to", required=True, help="target status name, e.g. Done")
    sp.add_argument("keys", nargs="+", help="issue keys, e.g. CLS-1 CLS-2")
    sp.set_defaults(fn=cmd_transition)

    sp = add("create", "create an issue")
    sp.add_argument("--type", default="Task")
    sp.add_argument("--summary", required=True)
    sp.add_argument("--desc")
    sp.add_argument("--team", choices=list(TEAMS))
    sp.add_argument("--assignee", help="accountId (resolve a name with `tasks`/user search)")
    sp.add_argument("--sprint", choices=["active", "none"], default="none")
    sp.set_defaults(fn=cmd_create)
    return p


def main():
    args = build_parser().parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
