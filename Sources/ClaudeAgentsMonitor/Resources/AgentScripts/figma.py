#!/usr/bin/env python3
"""figma.py — reference CLI for the Figma template agent.

Wraps the Figma REST API so the agent calls a tested command instead of curl.

Auth from the environment (token never printed):
    FIGMA_TOKEN / FIGMA_API_TOKEN   required — personal access token
Base: https://api.figma.com. FILE_KEY is the id from a Figma URL
(figma.com/file/<FILE_KEY>/…).

Stdlib only — `python3 figma.py <cmd>`.

Examples:
    python3 figma.py me
    python3 figma.py file <FILE_KEY>
    python3 figma.py node <FILE_KEY> 1:23
    python3 figma.py components <FILE_KEY>
    python3 figma.py comments <FILE_KEY>
    python3 figma.py image <FILE_KEY> 1:23 --format png
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

BASE = "https://api.figma.com"
TOKEN = os.environ.get("FIGMA_TOKEN") or os.environ.get("FIGMA_API_TOKEN", "")


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def get(path: str, params: dict | None = None):
    if not TOKEN:
        die("token not set (FIGMA_TOKEN / FIGMA_API_TOKEN)")
    url = f"{BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    req.add_header("X-Figma-Token", TOKEN)
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


# --- commands ----------------------------------------------------------------

def cmd_me(args):
    me = get("/v1/me")
    emit(args, me, ["Field", "Value"],
         [["handle", me.get("handle", "—")], ["email", me.get("email", "—")], ["id", me.get("id", "—")]])


def cmd_file(args):
    data = get(f"/v1/files/{args.key}", {"depth": 1})
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    print(f"{data.get('name', '—')}  (last modified {data.get('lastModified', '—')[:10]})")
    pages = (data.get("document", {}) or {}).get("children", [])
    print(table(["PAGE ID", "NAME"], [[p.get("id", "—"), p.get("name", "—")] for p in pages]))


def cmd_node(args):
    data = get(f"/v1/files/{args.key}/nodes", {"ids": args.node_id})
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    nodes = data.get("nodes", {})
    for nid, wrap in nodes.items():
        doc = (wrap or {}).get("document", {})
        print(f"{nid}  [{doc.get('type', '—')}]  {doc.get('name', '—')}")
        for child in doc.get("children", [])[:30]:
            print(f"  - {child.get('id')}  [{child.get('type')}]  {child.get('name')}")


def cmd_components(args):
    data = get(f"/v1/files/{args.key}/components")
    comps = (data.get("meta", {}) or {}).get("components", [])
    emit(args, comps, ["NODE ID", "NAME"],
         [[c.get("node_id", "—"), c.get("name", "—")[:70]] for c in comps])


def cmd_comments(args):
    data = get(f"/v1/files/{args.key}/comments")
    items = data.get("comments", [])
    emit(args, items, ["AUTHOR", "MESSAGE"],
         [[(c.get("user") or {}).get("handle", "—"), (c.get("message", "") or "")[:70]] for c in items])


def cmd_image(args):
    data = get(f"/v1/images/{args.key}", {"ids": args.node_id, "format": args.format})
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    images = data.get("images", {})
    for nid, url in images.items():
        print(f"{nid}: {url}")


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="raw JSON output")
    p = argparse.ArgumentParser(prog="figma.py", description="Figma agent CLI (stdlib only)",
                                parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)
    add = lambda n, h: sub.add_parser(n, help=h, parents=[common])

    add("me", "current user").set_defaults(fn=cmd_me)
    sp = add("file", "file name + pages"); sp.add_argument("key"); sp.set_defaults(fn=cmd_file)
    sp = add("node", "node tree"); sp.add_argument("key"); sp.add_argument("node_id"); sp.set_defaults(fn=cmd_node)
    sp = add("components", "file components"); sp.add_argument("key"); sp.set_defaults(fn=cmd_components)
    sp = add("comments", "file comments"); sp.add_argument("key"); sp.set_defaults(fn=cmd_comments)
    sp = add("image", "render node to image URL"); sp.add_argument("key"); sp.add_argument("node_id")
    sp.add_argument("--format", default="png", choices=["png", "jpg", "svg", "pdf"]); sp.set_defaults(fn=cmd_image)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    args.fn(args)
