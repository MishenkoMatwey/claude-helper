#!/usr/bin/env python3
"""gitlab.py — reference CLI for the GitLab template agent.

Wraps the GitLab REST API v4 so the agent calls a tested command instead of
hand-rolling curl. Read-focused (safe by default); creating MRs etc. is left to
explicit follow-up.

Auth & config from the environment (token never printed):
    GITLAB_TOKEN / GITLAB_API_TOKEN   required — Personal Access Token (PRIVATE-TOKEN)
    GITLAB_URL                        default https://gitlab.com

PROJECT is a numeric id or a URL-path "group/subgroup/repo" (auto URL-encoded).

Stdlib only — `python3 gitlab.py <cmd>`.

Examples:
    python3 gitlab.py me
    python3 gitlab.py projects --search portfolio
    python3 gitlab.py mrs group/repo --state opened
    python3 gitlab.py mr group/repo 42
    python3 gitlab.py issues group/repo --state opened
    python3 gitlab.py pipelines group/repo
    python3 gitlab.py branches group/repo
Add --json for raw output.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("GITLAB_URL", "https://gitlab.com").rstrip("/")
TOKEN = os.environ.get("GITLAB_TOKEN") or os.environ.get("GITLAB_API_TOKEN", "")
API = "/api/v4"


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def _pid(project: str) -> str:
    """Numeric id stays as-is; a path is URL-encoded per GitLab's convention."""
    return project if project.isdigit() else urllib.parse.quote(project, safe="")


def get(path: str, params: dict | None = None):
    if not TOKEN:
        die("token not set (GITLAB_TOKEN / GITLAB_API_TOKEN)")
    url = f"{BASE}{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    req.add_header("PRIVATE-TOKEN", TOKEN)
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        die(f"HTTP {e.code} on {path}: {e.read().decode(errors='replace')[:400]}", code=2)
    except urllib.error.URLError as e:
        die(f"network error on {path}: {e.reason}", code=2)


def table(headers, rows):
    if not rows:
        return "(пусто)"
    w = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            w[i] = max(w[i], len(str(c)))
    line = lambda cs: " | ".join(str(c).ljust(w[i]) for i, c in enumerate(cs))
    return "\n".join([line(headers), "-+-".join("-" * x for x in w), *[line(r) for r in rows]])


def emit(args, payload, headers=None, rows=None):
    if getattr(args, "json", False):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif rows is not None:
        print(table(headers, rows))
    else:
        print(payload)


# --- commands ---------------------------------------------------------------

def cmd_me(args):
    me = get("/user")
    emit(args, me, ["Field", "Value"],
         [["username", me.get("username", "—")],
          ["name", me.get("name", "—")],
          ["id", str(me.get("id", "—"))]])


def cmd_projects(args):
    params = {"membership": "true", "per_page": args.max, "order_by": "last_activity_at"}
    if args.search:
        params["search"] = args.search
    res = get("/projects", params)
    emit(args, res, ["ID", "PATH", "NAME"],
         [[str(p.get("id")), p.get("path_with_namespace", "—"), p.get("name", "—")[:40]] for p in res])


def cmd_mrs(args):
    res = get(f"/projects/{_pid(args.project)}/merge_requests",
              {"state": args.state, "per_page": args.max, "order_by": "updated_at"})
    emit(args, res, ["IID", "STATE", "AUTHOR", "TITLE"],
         [[str(m.get("iid")), m.get("state", "—"),
           (m.get("author") or {}).get("username", "—"), m.get("title", "—")[:60]] for m in res])


def cmd_mr(args):
    m = get(f"/projects/{_pid(args.project)}/merge_requests/{args.iid}")
    if args.json:
        print(json.dumps(m, ensure_ascii=False, indent=2))
        return
    print(f"!{m.get('iid')}  [{m.get('state')}]  {m.get('title')}")
    print(f"Author : {(m.get('author') or {}).get('username', '—')}")
    print(f"Branch : {m.get('source_branch')} → {m.get('target_branch')}")
    print(f"URL    : {m.get('web_url')}")


def cmd_issues(args):
    res = get(f"/projects/{_pid(args.project)}/issues",
              {"state": args.state, "per_page": args.max, "order_by": "updated_at"})
    emit(args, res, ["IID", "STATE", "ASSIGNEE", "TITLE"],
         [[str(i.get("iid")), i.get("state", "—"),
           (i.get("assignee") or {}).get("username", "—"), i.get("title", "—")[:60]] for i in res])


def cmd_pipelines(args):
    res = get(f"/projects/{_pid(args.project)}/pipelines", {"per_page": args.max})
    emit(args, res, ["ID", "STATUS", "REF", "UPDATED"],
         [[str(p.get("id")), p.get("status", "—"), p.get("ref", "—"),
           (p.get("updated_at", "") or "")[:19]] for p in res])


def cmd_branches(args):
    res = get(f"/projects/{_pid(args.project)}/repository/branches", {"per_page": args.max})
    emit(args, res, ["NAME", "DEFAULT", "MERGED"],
         [[b.get("name", "—"), str(b.get("default", False)), str(b.get("merged", False))] for b in res])


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="raw JSON output")
    common.add_argument("--max", type=int, default=20, help="max results (default 20)")
    p = argparse.ArgumentParser(prog="gitlab.py", description="GitLab agent CLI (stdlib only)",
                                parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)
    add = lambda n, h: sub.add_parser(n, help=h, parents=[common])

    add("me", "current user").set_defaults(fn=cmd_me)
    sp = add("projects", "your projects"); sp.add_argument("--search"); sp.set_defaults(fn=cmd_projects)
    sp = add("mrs", "merge requests"); sp.add_argument("project"); sp.add_argument("--state", default="opened"); sp.set_defaults(fn=cmd_mrs)
    sp = add("mr", "one merge request"); sp.add_argument("project"); sp.add_argument("iid"); sp.set_defaults(fn=cmd_mr)
    sp = add("issues", "issues"); sp.add_argument("project"); sp.add_argument("--state", default="opened"); sp.set_defaults(fn=cmd_issues)
    sp = add("pipelines", "recent pipelines"); sp.add_argument("project"); sp.set_defaults(fn=cmd_pipelines)
    sp = add("branches", "repository branches"); sp.add_argument("project"); sp.set_defaults(fn=cmd_branches)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    args.fn(args)
