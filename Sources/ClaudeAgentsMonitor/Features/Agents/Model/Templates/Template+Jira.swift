import Foundation

extension AgentTemplate {
    static let jira = AgentTemplate(
        id: "jira",
        name: "jira",
        icon: "checklist",
        assetIcon: "jira",
        color: "blue",
        description: "Jira specialist: issues, sprints, boards, epics — via Atlassian REST API and jira CLI.",
        model: "sonnet",
        suggestedTools: [.Read, .Glob, .Grep, .WebFetch],
        bashPresetIds: ["curl / network read", "Read-only utils"],
        bashCategories: ["Network", "Files"],
        suggestedSkillNames: [],
        suggestedPluginIds: [],
        secretsToSetup: [
            SecretField(
                key: "JIRA_API_TOKEN",
                label: "Atlassian API token",
                placeholder: "ATATT3xFfGF0…",
                help: "Create at id.atlassian.com/manage-profile/security/api-tokens. Used together with your email for Basic auth.",
                isOptional: false,
                providerIcon: "checklist",
                providerColor: "blue",
                providerName: "Jira"
            )
        ],
        plainVarsToSetup: [
            PlainVarField(
                key: "JIRA_BASE_URL",
                label: "Atlassian base URL",
                defaultValue: "",
                help: "Your Atlassian Cloud site root — e.g. https://<your-site>.atlassian.net. No trailing slash, no /jira suffix."
            ),
            PlainVarField(
                key: "JIRA_EMAIL",
                label: "Atlassian email",
                defaultValue: "",
                help: "Email of the Atlassian account that owns the API token."
            ),
            PlainVarField(
                key: "JIRA_DEFAULT_PROJECT",
                label: "Default project key",
                defaultValue: "",
                help: "Project key used when issue key is ambiguous — e.g. <KEY>-123. Leave empty to skip the project check.",
                isOptional: true
            )
        ],
        promptTemplate: """
        Ты — Jira специалист для Atlassian Cloud сайта `{JIRA_BASE_URL}`.

        ## Основной путь — скрипт `jira.py` (используй в первую очередь)

        Готовый CLI: `.claude/agents/scripts/jira.py` (запуск из корня проекта через `python3`).
        Он инкапсулирует REST-паттерны — **НЕ переписывай curl руками**, если задачу покрывает команда.
        Токен — ТОЛЬКО из Keychain: `export JIRA_API_TOKEN=$(security find-generic-password -s <service-из-секции-Variables> -a JIRA_API_TOKEN -w)` перед запуском. Email скрипт берёт сам из конфига jira-cli.
        Никогда не печатай токен.

        ```
        python3 .claude/agents/scripts/jira.py me                 # проверка подключения
        python3 .claude/agents/scripts/jira.py my-tasks           # мои задачи
        python3 .claude/agents/scripts/jira.py tasks "Имя"        # задачи человека
        python3 .claude/agents/scripts/jira.py ticket {JIRA_DEFAULT_PROJECT}-123
        python3 .claude/agents/scripts/jira.py sprint [--stats]   # спринт / статистика
        python3 .claude/agents/scripts/jira.py epics --team <team>
        python3 .claude/agents/scripts/jira.py backlog --team <team>
        python3 .claude/agents/scripts/jira.py boards
        python3 .claude/agents/scripts/jira.py search "<JQL>" --max 30
        python3 .claude/agents/scripts/jira.py create --type Bug --summary "..." --assignee <accountId> --sprint active
        ```

        `--json` к любой команде для машинного вывода; `python3 .../jira.py --help` — полный список.
        Команды читают `JIRA_BASE_URL`/`JIRA_PROJECT` и т.п. из env, если заданы.

        ## Fallback: HTTP REST (для того, что скрипт не покрывает)
        Basic auth: `curl -u "{JIRA_EMAIL}:$JIRA_API_TOKEN" -H "Accept: application/json" ...`.
        Поиск — новый endpoint `POST /rest/api/3/search/jql` (НЕ `/search`). Парсинг через `jq`.
        Описания/комментарии — в ADF (Atlassian Document Format), не plain text.

        ## Правила
        - НИКОГДА не делай destructive операций (delete issue/sprint) без подтверждения.
        - Транзишены статуса — только по явному запросу.
        - Если в скрипте не хватает команды — используй HTTP fallback и предложи дописать команду в `jira.py`.
        """,
        validation: TemplateValidation(
            label: "Verify both HTTP REST and jira CLI work end-to-end",
            command: """
            email="{JIRA_EMAIL}"
            base="{JIRA_BASE_URL}"
            token="{JIRA_API_TOKEN}"
            project="{JIRA_DEFAULT_PROJECT}"

            # Strip control chars + leading/trailing whitespace that often sneak in via copy-paste.
            email=$(printf '%s' "$email" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            base=$(printf  '%s' "$base"  | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            project=$(printf '%s' "$project" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            base="${base%/}"

            # Token strict scrub: Atlassian Cloud tokens are base64url + '=' suffix. Remove anything else
            # (zero-width Unicode, smart quotes, NBSP, control chars — common when pasted from chat).
            token_raw="$token"
            token=$(LC_ALL=C printf '%s' "$token" | LC_ALL=C tr -cd 'A-Za-z0-9_=+/-')
            if [ "${#token_raw}" != "${#token}" ]; then
              echo "ℹ Token had ${#token_raw} → ${#token} chars after cleanup (removed $((${#token_raw} - ${#token})) invisible/illegal char(s))."
            fi

            if [ -z "$email" ] || [ -z "$base" ] || [ -z "$token" ]; then
              echo "✗ Email, base URL and token are all required."
              exit 1
            fi

            # Token sanity.
            case "$token" in
              ghp_*|gho_*|github_pat_*|glpat-*)
                echo "✗ This looks like a Git provider token, not an Atlassian one. Get yours at id.atlassian.com/manage-profile/security/api-tokens."
                exit 1 ;;
            esac

            case "$base" in
              http://*|https://*) : ;;
              *) echo "✗ Base URL must start with http:// or https:// — got '$base'"; exit 1 ;;
            esac

            # ─── A. HTTP REST ─────────────────────────────────────────────
            echo "── HTTP REST ──"

            tmp=$(mktemp)
            code=$(curl -sS -o "$tmp" -w "%{http_code}" \\
                -u "$email:$token" \\
                -H "Accept: application/json" \\
                "$base/rest/api/3/myself")
            body=$(cat "$tmp"); rm -f "$tmp"

            http_ok=0
            case "$code" in
              200)
                login=$(echo "$body" | sed -n 's/.*"displayName":"\\([^"]*\\)".*/\\1/p')
                acct=$(echo "$body"  | sed -n 's/.*"accountId":"\\([^"]*\\)".*/\\1/p')
                echo "✓ /rest/api/3/myself — $login (accountId: $acct)"
                http_ok=1
                ;;
              401|403)
                echo "✗ Auth failed (HTTP $code)."
                echo "  email used:  '$email' (len=${#email})"
                echo "  token len:   ${#token} chars, prefix: ${token:0:8}…"
                echo "  base URL:    $base"
                echo "  Hints:"
                echo "  • Re-copy the API token at id.atlassian.com/manage-profile/security/api-tokens"
                echo "  • Email must be the one that owns the token (case matters? no, but typos do)"
                echo "  • Make sure you didn't accidentally paste a trailing space — already auto-trimmed, but double-check"
                echo "  ── raw response ──"
                echo "$body" | head -3
                exit 1 ;;
              404)
                echo "✗ Base URL '$base' did not resolve to an Atlassian site (HTTP 404)."
                exit 1 ;;
              *)
                echo "✗ Unexpected response (HTTP $code) from $base/rest/api/3/myself"
                echo "$body" | head -3
                exit 1 ;;
            esac

            # JQL endpoint check.
            jql_code=$(curl -sS -o /dev/null -w "%{http_code}" \\
                -u "$email:$token" \\
                -H "Accept: application/json" -H "Content-Type: application/json" \\
                --data '{"jql":"assignee = currentUser()","maxResults":1,"fields":["summary"]}' \\
                "$base/rest/api/3/search/jql")
            if [ "$jql_code" = "200" ]; then
              echo "✓ POST /rest/api/3/search/jql — reachable"
            else
              echo "⚠ JQL endpoint returned HTTP $jql_code (non-fatal — auth still works)"
            fi

            # Default project access (if provided).
            if [ -n "$project" ]; then
              tmp=$(mktemp)
              p_code=$(curl -sS -o "$tmp" -w "%{http_code}" \\
                  -u "$email:$token" \\
                  -H "Accept: application/json" \\
                  "$base/rest/api/3/project/$project")
              p_body=$(cat "$tmp"); rm -f "$tmp"
              case "$p_code" in
                200)
                  name=$(echo "$p_body" | sed -n 's/.*"name":"\\([^"]*\\)".*/\\1/p' | head -1)
                  echo "✓ Project $project accessible: $name"
                  ;;
                404) echo "✗ Project '$project' not found on this site."; exit 1 ;;
                403) echo "✗ Token has no permission to read project '$project'."; exit 1 ;;
                *)   echo "⚠ Project $project check returned HTTP $p_code (non-fatal)" ;;
              esac
            else
              echo "ℹ No default project set — skipping project check."
            fi

            # ─── B. jira CLI (Go, ankitpokhrel/jira-cli) ──────────────────
            echo ""
            echo "── jira CLI ──"

            jira_bin=""
            if [ -x /opt/homebrew/bin/jira ]; then
              jira_bin="/opt/homebrew/bin/jira"
            elif command -v jira >/dev/null 2>&1; then
              jira_bin=$(command -v jira)
            fi

            if [ -z "$jira_bin" ]; then
              echo "ℹ jira CLI not installed — HTTP path will be used exclusively."
              echo "  Install (optional): brew install ankitpokhrel/jira-cli/jira-cli"
            else
              echo "✓ jira binary: $jira_bin"

              cfg="$HOME/.config/.jira/.config.yml"
              if [ ! -f "$cfg" ]; then
                echo "⚠ No config at $cfg — run 'jira init' once to enable CLI. HTTP path still works."
              else
                echo "✓ config: $cfg"
                # Compare configured server with the validated base URL.
                cfg_server=$(grep -E '^server:' "$cfg" | head -1 | sed 's/server:[[:space:]]*//; s/[[:space:]]*$//; s|/$||' | tr -d '"'"'")
                base_no_slash="${base%/}"
                if [ -n "$cfg_server" ] && [ "$cfg_server" != "$base_no_slash" ]; then
                  echo "⚠ CLI config server ($cfg_server) differs from base URL ($base_no_slash)."
                fi
                # Smoke test — JIRA_API_TOKEN env is what jira-cli reads.
                me_out=$(JIRA_API_TOKEN="$token" "$jira_bin" me 2>&1)
                if [ $? -eq 0 ]; then
                  echo "✓ 'jira me' → $me_out"
                else
                  echo "⚠ 'jira me' failed:"
                  echo "$me_out" | head -3
                  echo "  Re-run 'jira init' if email/server in config are stale. HTTP path still works."
                fi
              fi
            fi

            echo ""
            if [ "$http_ok" -eq 1 ]; then
              echo "Token is valid — agent ready."
              exit 0
            fi
            exit 1
            """,
            successHint: "Both HTTP REST and (if installed) jira CLI authenticate against your site."
        ),
        bundledScripts: ["jira.py"]
    )
}
