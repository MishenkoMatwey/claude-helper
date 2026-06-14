#!/usr/bin/env python3
"""confluence.py — reference CLI for the Confluence template agent.

Wraps the Confluence Cloud REST API (same Atlassian token as Jira) so the agent
calls a tested command instead of hand-rolling curl + jq.

Auth & config from the environment (nothing secret is printed):
    JIRA_API_TOKEN / CONFLUENCE_API_TOKEN   required — Atlassian API token
    JIRA_EMAIL / CONFLUENCE_EMAIL           email (Basic auth); else read from jira-cli config
    CONFLUENCE_BASE_URL / JIRA_BASE_URL     default https://clussters.atlassian.net
The Confluence REST root is <base>/wiki/rest/api.

Stdlib only — `python3 confluence.py <cmd>`.

Examples:
    python3 confluence.py me
    python3 confluence.py spaces
    python3 confluence.py pages --space WaaS
    python3 confluence.py page "Onboarding" [--space WaaS]
    python3 confluence.py search "rate limit"
    python3 confluence.py children 65541
    python3 confluence.py get 123456            # page body as text
Add --json for raw output.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def _email_from_jira_cli() -> str:
    cfg = os.path.expanduser("~/.config/.jira/.config.yml")
    try:
        with open(cfg, encoding="utf-8") as fh:
            for line in fh:
                if line.strip().startswith("login:"):
                    return line.split(":", 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return ""


BASE = (os.environ.get("CONFLUENCE_BASE_URL")
        or os.environ.get("JIRA_BASE_URL")
        or "https://clussters.atlassian.net").rstrip("/")
EMAIL = (os.environ.get("CONFLUENCE_EMAIL") or os.environ.get("JIRA_EMAIL") or _email_from_jira_cli())
TOKEN = os.environ.get("CONFLUENCE_API_TOKEN") or os.environ.get("JIRA_API_TOKEN", "")
API = "/wiki/rest/api"


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def get(path: str, params: dict | None = None) -> dict:
    if not TOKEN:
        die("API token not set (JIRA_API_TOKEN / CONFLUENCE_API_TOKEN)")
    if not EMAIL:
        die("email not set (JIRA_EMAIL / CONFLUENCE_EMAIL)")
    url = f"{BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    auth = base64.b64encode(f"{EMAIL}:{TOKEN}".encode()).decode()
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Basic {auth}")
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


def _strip_html(html: str) -> str:
    return re.sub(r"\s+\n", "\n", re.sub(r"<[^>]+>", "", html)).strip()


# --- commands ---------------------------------------------------------------

def cmd_me(args):
    me = get(f"{API}/user/current")
    emit(args, me, ["Field", "Value"],
         [["displayName", me.get("displayName", "—")],
          ["accountId", me.get("accountId", "—")],
          ["type", me.get("type", "—")]])


def cmd_spaces(args):
    data = get(f"{API}/space", {"limit": args.max, "type": "global"})
    res = data.get("results", [])
    emit(args, res, ["KEY", "NAME", "TYPE"],
         [[s.get("key", "—"), s.get("name", "—"), s.get("type", "—")] for s in res])


def cmd_pages(args):
    params = {"type": "page", "limit": args.max, "expand": "version"}
    if args.space:
        params["spaceKey"] = args.space
    data = get(f"{API}/content", params)
    res = data.get("results", [])
    emit(args, res, ["ID", "TITLE", "UPDATED"],
         [[p.get("id", "—"), p.get("title", "—")[:70],
           (p.get("version", {}).get("when", "") or "")[:10]] for p in res])


def cmd_page(args):
    params = {"title": args.title, "type": "page", "limit": args.max, "expand": "version,space"}
    if args.space:
        params["spaceKey"] = args.space
    data = get(f"{API}/content", params)
    res = data.get("results", [])
    if not res:
        die(f"no page titled '{args.title}'" + (f" in space {args.space}" if args.space else ""))
    emit(args, res, ["ID", "TITLE", "SPACE", "URL"],
         [[p.get("id"), p.get("title", "—")[:60],
           p.get("space", {}).get("key", "—"),
           f"{BASE}/wiki{p.get('_links', {}).get('webui', '')}"] for p in res])


def cmd_search(args):
    cql = f'text ~ "{args.text}"'
    if args.space:
        cql += f' AND space = "{args.space}"'
    data = get(f"{API}/search", {"cql": cql, "limit": args.max})
    res = data.get("results", [])
    rows = []
    for r in res:
        c = r.get("content", {})
        rows.append([c.get("id", "—"), c.get("type", "—"), (r.get("title") or c.get("title", "—"))[:70]])
    emit(args, res, ["ID", "TYPE", "TITLE"], rows)


def cmd_children(args):
    data = get(f"{API}/content/{args.page_id}/child/page", {"limit": args.max})
    res = data.get("results", [])
    emit(args, res, ["ID", "TITLE"], [[p.get("id"), p.get("title", "—")[:80]] for p in res])


def cmd_get(args):
    page = get(f"{API}/content/{args.page_id}", {"expand": "body.storage,version,space"})
    if args.json:
        print(json.dumps(page, ensure_ascii=False, indent=2))
        return
    body = page.get("body", {}).get("storage", {}).get("value", "")
    print(f"{page.get('title')}  [{page.get('space', {}).get('key', '—')}]")
    print(f"URL: {BASE}/wiki{page.get('_links', {}).get('webui', '')}\n")
    print(_strip_html(body)[:4000])


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="raw JSON output")
    common.add_argument("--max", type=int, default=25, help="max results (default 25)")
    p = argparse.ArgumentParser(prog="confluence.py", description="Confluence agent CLI (stdlib only)",
                                parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)
    add = lambda n, h: sub.add_parser(n, help=h, parents=[common])

    add("me", "current user").set_defaults(fn=cmd_me)
    add("spaces", "list spaces").set_defaults(fn=cmd_spaces)
    sp = add("pages", "pages of a space"); sp.add_argument("--space"); sp.set_defaults(fn=cmd_pages)
    sp = add("page", "find page by title"); sp.add_argument("title"); sp.add_argument("--space"); sp.set_defaults(fn=cmd_page)
    sp = add("search", "full-text (CQL) search"); sp.add_argument("text"); sp.add_argument("--space"); sp.set_defaults(fn=cmd_search)
    sp = add("children", "child pages of a page"); sp.add_argument("page_id"); sp.set_defaults(fn=cmd_children)
    sp = add("get", "page body as text"); sp.add_argument("page_id"); sp.set_defaults(fn=cmd_get)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    args.fn(args)
