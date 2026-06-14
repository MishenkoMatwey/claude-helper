#!/usr/bin/env python3
"""db.py — reference CLI for the database (read-only) template agent.

Safe, read-only Postgres access: the connection is opened READ ONLY at the driver
level AND every statement is checked to be a read (SELECT/WITH/EXPLAIN/SHOW/...),
with a statement timeout and a row cap. The agent gets tables/schema/sample/query
without hand-rolling psycopg2 each task.

Connection from standard libpq env vars (psycopg2 reads them natively):
    PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE   (PGSSLMODE default: require)
or a single DSN:
    --dsn "postgresql://user:pass@host:6432/dbname?sslmode=require"
Fetch the password from Keychain and pass it via env, e.g.:
    PGPASSWORD=$(security find-generic-password -s <svc> -a <KEY> -w) python3 db.py tables

Requires psycopg2 (no stdlib Postgres driver). Everything else is stdlib.

Examples:
    python3 db.py tables [--schema public]
    python3 db.py schema portfolio
    python3 db.py sample portfolio --max 10
    python3 db.py count portfolio
    python3 db.py query "SELECT id, name FROM portfolio WHERE active LIMIT 20"
Add --json for raw output.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("error: psycopg2 not installed — `pip3 install psycopg2-binary`", file=sys.stderr)
    sys.exit(3)

READ_PREFIXES = ("select", "with", "explain", "show", "table", "values")
STATEMENT_TIMEOUT_MS = int(os.environ.get("DB_STATEMENT_TIMEOUT_MS", "15000"))


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def _is_read_only(sql: str) -> bool:
    # Strip line/block comments, then require a single read statement.
    s = re.sub(r"--[^\n]*", " ", sql)
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S).strip().rstrip(";").strip()
    if ";" in s:  # no multi-statement
        return False
    return s.lower().startswith(READ_PREFIXES)


def connect(args):
    try:
        os.environ.setdefault("PGSSLMODE", os.environ.get("PGSSLMODE", "require"))
        if args.dsn:
            conn = psycopg2.connect(args.dsn)
        elif getattr(args, "db", None):
            # Target one database on the host (host/user/password still from PG* env).
            conn = psycopg2.connect(dbname=args.db)
        else:
            conn = psycopg2.connect()  # uses PG* env vars
        conn.set_session(readonly=True, autocommit=True)  # enforce read-only at the driver
        return conn
    except psycopg2.Error as e:
        die(f"connection failed: {str(e).strip()}", code=2)


def run_read(conn, sql: str, max_rows: int):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(f"SET statement_timeout = {STATEMENT_TIMEOUT_MS}")
        cur.execute(sql)
        return cur.fetchmany(max_rows)


def table_out(rows, args):
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2, default=str))
        return
    if not rows:
        print("(0 rows)")
        return
    cols = list(rows[0].keys())
    widths = {c: len(c) for c in cols}
    for r in rows:
        for c in cols:
            widths[c] = max(widths[c], len(str(r.get(c, ""))))
    line = lambda vals: " | ".join(str(v).ljust(widths[c]) for c, v in zip(cols, vals))
    print(line(cols))
    print("-+-".join("-" * widths[c] for c in cols))
    for r in rows:
        print(line([r.get(c, "") for c in cols]))
    print(f"\n({len(rows)} row{'s' if len(rows) != 1 else ''})")


def _safe_ident(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?", name):
        die(f"invalid identifier: {name!r}")
    return name


# --- commands ----------------------------------------------------------------

def cmd_databases(args):
    conn = connect(args)
    rows = run_read(conn, """
        SELECT datname FROM pg_database
        WHERE datistemplate = false AND datallowconn
        ORDER BY datname
    """, args.max)
    table_out(rows, args)


def cmd_tables(args):
    conn = connect(args)
    rows = run_read(conn, """
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_type = 'BASE TABLE' AND table_schema = %(s)s
        ORDER BY table_name
    """.replace("%(s)s", "'%s'" % _safe_ident(args.schema)), args.max)
    table_out(rows, args)


def cmd_schema(args):
    conn = connect(args)
    t = _safe_ident(args.table)
    rows = run_read(conn, f"""
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_name = '{t.split('.')[-1]}'
        ORDER BY ordinal_position
    """, args.max)
    table_out(rows, args)


def cmd_sample(args):
    conn = connect(args)
    t = _safe_ident(args.table)
    table_out(run_read(conn, f"SELECT * FROM {t} LIMIT {int(args.max)}", args.max), args)


def cmd_count(args):
    conn = connect(args)
    t = _safe_ident(args.table)
    table_out(run_read(conn, f"SELECT count(*) AS count FROM {t}", 1), args)


def cmd_query(args):
    if not _is_read_only(args.sql):
        die("refused: only read-only statements allowed (SELECT/WITH/EXPLAIN/SHOW), single statement")
    conn = connect(args)
    table_out(run_read(conn, args.sql, args.max), args)


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="raw JSON output")
    common.add_argument("--max", type=int, default=50, help="max rows (default 50)")
    common.add_argument("--dsn", help="postgresql://… (else uses PG* env vars)")
    common.add_argument("--db", help="target one database on the host (overrides PGDATABASE)")
    p = argparse.ArgumentParser(prog="db.py", description="Read-only Postgres CLI (psycopg2)",
                                parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)
    add = lambda n, h: sub.add_parser(n, help=h, parents=[common])

    add("databases", "list databases on the host").set_defaults(fn=cmd_databases)
    sp = add("tables", "list tables"); sp.add_argument("--schema", default="public"); sp.set_defaults(fn=cmd_tables)
    sp = add("schema", "columns of a table"); sp.add_argument("table"); sp.set_defaults(fn=cmd_schema)
    sp = add("sample", "first N rows"); sp.add_argument("table"); sp.set_defaults(fn=cmd_sample)
    sp = add("count", "row count"); sp.add_argument("table"); sp.set_defaults(fn=cmd_count)
    sp = add("query", "run a read-only SQL query"); sp.add_argument("sql"); sp.set_defaults(fn=cmd_query)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    args.fn(args)
