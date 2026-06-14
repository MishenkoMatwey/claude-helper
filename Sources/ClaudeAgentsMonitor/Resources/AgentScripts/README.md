# Agent scripts

Thin, tested CLIs that template agents call instead of hand-rolling `curl` + `jq`
every task. They cut tokens (one command vs. re-derived HTTP), remove escaping /
endpoint footguns, and give a stable output contract.

## Design rules (keep them ideal)

- **Stdlib only** — runnable as `python3 <script>.py` with no `pip install`.
- **Secrets from the environment** (`*_API_TOKEN`, email) — never printed, never
  hard-coded. Project config (IDs, custom fields) has env-overridable defaults.
- **Single-purpose subcommands** named after real workflows.
- **Two output modes**: human table/text by default, `--json` for machine use.
- **Clear errors** to stderr with a non-zero exit; no secret leakage in messages.

## `jira.py`

```sh
export JIRA_API_TOKEN=...           # required (Atlassian API token)
export JIRA_EMAIL=you@example.com   # required
# export JIRA_BASE_URL=https://your-site.atlassian.net   # default: clussters

python3 jira.py me
python3 jira.py my-tasks
python3 jira.py tasks "Иван"
python3 jira.py ticket CLS-3396
python3 jira.py sprint [--stats]
python3 jira.py epics --team wasabi
python3 jira.py backlog --team bbq
python3 jira.py boards
python3 jira.py search "project = CLS AND statusCategory != Done" --max 20
python3 jira.py create --type Bug --summary "..." --team wasabi --assignee <accountId> --sprint active
```

Add `--json` to any command for raw output; `--max N` to bound result size.

## `confluence.py`

Same Atlassian token as Jira. `me · spaces · pages --space K · page "title" · search "text" · children <id> · get <id>`.

## `gitlab.py`

GitLab API v4. Token from `GITLAB_TOKEN`; `GITLAB_URL` for self-hosted.
`me · projects [--search] · mrs <group/repo> · mr <…> <iid> · issues <…> · pipelines <…> · branches <…>`.
PROJECT is a numeric id or a URL-path `group/repo` (auto URL-encoded).

## `db.py`

**Read-only** Postgres (requires `psycopg2`). Connection via libpq env vars
(`PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE`) or `--dsn`. Every statement is
checked to be a read; connection is opened READ ONLY; statement timeout + row cap.
`tables · schema <t> · sample <t> · count <t> · query "<SELECT…>"`.

## `figma.py`

Figma REST v1. Token from `FIGMA_TOKEN`/`FIGMA_API_TOKEN`.
`me · file <KEY> · node <KEY> <id> · components <KEY> · comments <KEY> · image <KEY> <id> --format png`.

> `jira.py` also has `release-notes --version <fixVersion> [--team …]` → grouped markdown with issue links.

## How agents get them (automatic)

These files are bundled as app resources. When an agent is created from a
template that declares `bundledScripts`, the app: (1) copies the script into
`<project>/.claude/agents/scripts/`, (2) grants `Bash(python3:*)`, (3) the
template prompt tells the agent to call `python3 .claude/agents/scripts/<x>.py`.

Templates → scripts: `jira → jira.py`, `confluence → confluence.py`, `git → gitlab.py`, `database → db.py`, `figma → figma.py`.
To wire an existing (non-template) agent: copy the script into its project's
`scripts/`, add `Bash(python3:*)`, reference it in the prompt.
