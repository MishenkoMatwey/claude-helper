import Foundation

extension AgentTemplate {
    static let confluence = AgentTemplate(
        id: "confluence",
        name: "confluence",
        icon: "doc.richtext",
        assetIcon: "confluence",
        color: "purple",
        description: "Confluence specialist: spaces, pages, search and child trees — via Atlassian REST API v2.",
        model: "sonnet",
        suggestedTools: [.Read, .Glob, .Grep, .WebFetch],
        bashPresetIds: ["curl / network read", "Read-only utils"],
        bashCategories: ["Network", "Files"],
        suggestedSkillNames: [],
        suggestedPluginIds: [],
        secretsToSetup: [
            SecretField(
                key: "CONFLUENCE_API_TOKEN",
                label: "Atlassian API token",
                placeholder: "ATATT3xFfGF0…",
                help: "Same token as Jira works for Confluence — create at id.atlassian.com/manage-profile/security/api-tokens.",
                isOptional: false,
                providerIcon: "doc.richtext",
                providerColor: "purple",
                providerName: "Confluence"
            )
        ],
        plainVarsToSetup: [
            PlainVarField(
                key: "CONFLUENCE_BASE_URL",
                label: "Confluence base URL",
                defaultValue: "",
                help: "Atlassian site URL — e.g. https://<your-site>.atlassian.net. The /wiki suffix is appended automatically if missing."
            ),
            PlainVarField(
                key: "CONFLUENCE_EMAIL",
                label: "Atlassian email",
                defaultValue: "",
                help: "Email of the Atlassian account that owns the API token."
            ),
            PlainVarField(
                key: "CONFLUENCE_DEFAULT_SPACE",
                label: "Default space key",
                defaultValue: "",
                help: "Space key to use when ambiguous. Leave empty to skip the space check.",
                isOptional: true
            )
        ],
        promptTemplate: """
        Ты — Confluence специалист для сайта `{CONFLUENCE_BASE_URL}`.

        ## Основной путь — скрипт `confluence.py` (используй в первую очередь)
        Готовый CLI: `.claude/agents/scripts/confluence.py` (через `python3`, из корня проекта).
        **НЕ переписывай curl руками**, если задачу покрывает команда. Токен — ТОЛЬКО из Keychain (export CONFLUENCE_API_TOKEN=$(security ... -a CONFLUENCE_API_TOKEN -w) перед запуском); email — из конфига jira-cli.
        ```
        python3 .claude/agents/scripts/confluence.py spaces
        python3 .claude/agents/scripts/confluence.py pages --space <KEY>
        python3 .claude/agents/scripts/confluence.py page "<заголовок>" [--space <KEY>]
        python3 .claude/agents/scripts/confluence.py search "<текст>"
        python3 .claude/agents/scripts/confluence.py children <PAGE_ID>
        python3 .claude/agents/scripts/confluence.py get <PAGE_ID>
        ```
        `--json` к любой команде; `--help` — полный список. Если команды не хватает — HTTP fallback ниже.

        ## Авторизация
        - Basic auth: email + API token → `curl -u "{CONFLUENCE_EMAIL}:$CONFLUENCE_API_TOKEN" ...`
        - Token лежит в Keychain как `CONFLUENCE_API_TOKEN`. Никогда не печатай его.

        ## HTTP cookbook (proven working — copy-paste ready)
        ```bash
        EMAIL="{CONFLUENCE_EMAIL}"
        BASE="{CONFLUENCE_BASE_URL}"      # обязательно с /wiki, без trailing slash
        # CONFLUENCE_API_TOKEN уже в env (Keychain → env при запуске агента)
        AUTH=( -u "$EMAIL:$CONFLUENCE_API_TOKEN" -H "Accept: application/json" )
        ```
        Парсинг — через `jq`. Для CQL — URL-encode значения через `--data-urlencode` + `--get`, не вручную.

        ### Список spaces
        ```bash
        curl -s "${AUTH[@]}" "$BASE/api/v2/spaces?limit=50" \\
          | jq -r '.results[] | "\\(.id)  \\(.key)  \\(.name)"'
        ```

        ### Space по ключу → ID
        ```bash
        curl -s "${AUTH[@]}" --get --data-urlencode "keys={CONFLUENCE_DEFAULT_SPACE}" \\
          "$BASE/api/v2/spaces" \\
          | jq -r '.results[0] | "id=\\(.id)  key=\\(.key)  \\(.name)"'
        ```

        ### Страницы space (top-level, постранично)
        ```bash
        curl -s "${AUTH[@]}" "$BASE/api/v2/spaces/<spaceId>/pages?limit=50" \\
          | jq -r '.results[] | "\\(.id)  \\(.title)"'
        ```

        ### Страница по ID — тело в storage (XHTML) или ADF
        ```bash
        # storage (родной Confluence XHTML с макросами)
        curl -s "${AUTH[@]}" "$BASE/api/v2/pages/<pageId>?body-format=storage" \\
          | jq -r '.title, .body.storage.value'

        # ADF (как в Jira)
        curl -s "${AUTH[@]}" "$BASE/api/v2/pages/<pageId>?body-format=atlas_doc_format" | jq .
        ```

        ### Дочерние страницы
        ```bash
        curl -s "${AUTH[@]}" "$BASE/api/v2/pages/<pageId>/children?limit=50" \\
          | jq -r '.results[] | "\\(.id)  \\(.title)"'
        ```

        ### Поиск по тексту (CQL — пока v1, на v2 ещё нет полнотекста)
        ```bash
        curl -s "${AUTH[@]}" \\
          --get --data-urlencode 'cql=text ~ "<phrase>" AND space = {CONFLUENCE_DEFAULT_SPACE}' \\
          --data-urlencode "limit=10" \\
          "$BASE/rest/api/search" \\
          | jq -r '.results[] | "\\(.content.id)  [\\(.content.type)]  \\(.title)  \\(.url)"'
        ```

        ### Найти страницу по точному title в space (v1)
        ```bash
        curl -s "${AUTH[@]}" \\
          --get --data-urlencode "spaceKey={CONFLUENCE_DEFAULT_SPACE}" \\
          --data-urlencode "title=<TITLE>" \\
          --data-urlencode "expand=body.storage,version" \\
          "$BASE/rest/api/content" \\
          | jq -r '.results[0] | "id=\\(.id)  v=\\(.version.number)\\n\\(.body.storage.value)"'
        ```

        ### Обновить страницу (увеличить version.number на 1)
        ```bash
        curl -s "${AUTH[@]}" -X PUT -H "Content-Type: application/json" \\
          --data '{"id":"<pageId>","status":"current","title":"<title>","spaceId":"<spaceId>","body":{"representation":"storage","value":"<XHTML>"},"version":{"number":<N+1>,"message":"update"}}' \\
          "$BASE/api/v2/pages/<pageId>"
        ```

        ## Готовые сценарии (русские триггеры)
        - `пространства` → `GET /api/v2/spaces`
        - `страницы <space>` → resolve space → `GET /api/v2/spaces/<id>/pages`
        - `страница <название>` → v1 content?title=… с expand=body.storage
        - `найди <текст>` → v1 `/rest/api/search` с CQL `text ~ "<текст>"`
        - `дочерние <PAGE_ID>` → `GET /api/v2/pages/<id>/children`

        ## Discovery
        - Чтобы узнать spaceId по ключу: `GET /api/v2/spaces?keys=<KEY>` → `.results[0].id`
        - Все доступные spaces: `GET /api/v2/spaces?limit=250` (пагинация через Link header)

        ## Формат body
        - `storage` format = XHTML с макросами Atlassian. При создании/обновлении страниц — body.storage.value + body.storage.representation="storage".
        - `view` format = отрендеренный HTML (read-only).
        - `atlas_doc_format` = ADF (как в Jira); поддерживается на v2.

        ## Правила
        - НИКОГДА не delete page без явного подтверждения.
        - При обновлении страницы — увеличить `version.number` на 1.
        - Для CQL — спецсимволы (`"`, `\\`) экранируй; запросы кодируй для URL.
        - Пагинация v2 — Link header с `next` URL. v1 — `start`/`limit` + `_links.next`.
        """,
        validation: TemplateValidation(
            label: "Verify Atlassian token has Confluence access",
            command: """
            email="{CONFLUENCE_EMAIL}"
            base="{CONFLUENCE_BASE_URL}"
            token="{CONFLUENCE_API_TOKEN}"
            space="{CONFLUENCE_DEFAULT_SPACE}"

            email=$(printf '%s' "$email" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            base=$(printf  '%s' "$base"  | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            space=$(printf '%s' "$space" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            base="${base%/}"

            # Confluence Cloud lives under /wiki — auto-append if user pasted just the Atlassian
            # site root. Strip first to handle '/wiki/' or duplicate suffixes cleanly.
            base_input="$base"
            base="${base%/wiki}"
            base="${base}/wiki"
            if [ "$base_input" != "$base" ]; then
              echo "ℹ Normalized base URL → $base"
            fi

            # Token strict scrub: see Jira template for rationale.
            token_raw="$token"
            token=$(LC_ALL=C printf '%s' "$token" | LC_ALL=C tr -cd 'A-Za-z0-9_=+/-')
            if [ "${#token_raw}" != "${#token}" ]; then
              echo "ℹ Token had ${#token_raw} → ${#token} chars after cleanup (removed $((${#token_raw} - ${#token})) invisible/illegal char(s))."
            fi

            if [ -z "$email" ] || [ -z "$base" ] || [ -z "$token" ]; then
              echo "✗ Email, base URL and token are all required."
              exit 1
            fi

            case "$token" in
              ghp_*|gho_*|github_pat_*|glpat-*)
                echo "✗ This looks like a Git provider token, not an Atlassian one."
                exit 1 ;;
            esac

            case "$base" in
              http://*|https://*) : ;;
              *) echo "✗ Base URL must start with http:// or https:// — got '$base'"; exit 1 ;;
            esac

            # 1. v2 /spaces — validates token + Confluence access.
            tmp=$(mktemp)
            code=$(curl -sS -o "$tmp" -w "%{http_code}" \\
                -u "$email:$token" \\
                -H "Accept: application/json" \\
                "$base/api/v2/spaces?limit=1")
            body=$(cat "$tmp"); rm -f "$tmp"

            case "$code" in
              200)
                first=$(echo "$body" | sed -n 's/.*"name":"\\([^"]*\\)".*/\\1/p' | head -1)
                if [ -n "$first" ]; then
                  echo "✓ Confluence v2 reachable — first space: $first"
                else
                  echo "✓ Confluence v2 reachable (no spaces visible to this token)"
                fi
                ;;
              401|403)
                echo "✗ Auth failed (HTTP $code)."
                echo "  email used:  '$email' (len=${#email})"
                echo "  token len:   ${#token} chars, prefix: ${token:0:8}…"
                echo "  base URL:    $base"
                echo "  Hints:"
                echo "  • Re-copy the API token at id.atlassian.com/manage-profile/security/api-tokens"
                echo "  • Base URL must include /wiki — e.g. https://<site>.atlassian.net/wiki"
                echo "  • Trailing spaces auto-trimmed — but double-check the email for typos"
                echo "  ── raw response ──"
                echo "$body" | head -3
                exit 1 ;;
              404)
                echo "✗ /api/v2/spaces not found at '$base'. Base URL probably wrong — should end with '/wiki'."
                exit 1 ;;
              *)
                echo "✗ Unexpected response (HTTP $code) from $base/api/v2/spaces"
                echo "$body" | head -3
                exit 1 ;;
            esac

            # 2. Default space access (if provided).
            if [ -n "$space" ]; then
              tmp=$(mktemp)
              s_code=$(curl -sS -o "$tmp" -w "%{http_code}" \\
                  -u "$email:$token" \\
                  -H "Accept: application/json" \\
                  --get --data-urlencode "keys=$space" \\
                  "$base/api/v2/spaces")
              s_body=$(cat "$tmp"); rm -f "$tmp"
              if [ "$s_code" = "200" ]; then
                sid=$(echo "$s_body" | sed -n 's/.*"id":"\\([0-9]*\\)".*/\\1/p' | head -1)
                if [ -z "$sid" ]; then
                  sid=$(echo "$s_body" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p' | head -1)
                fi
                if [ -n "$sid" ]; then
                  echo "✓ Space '$space' accessible — id: $sid"
                else
                  echo "✗ Space '$space' not found or not visible to this token."
                  exit 1
                fi
              else
                echo "⚠ Space lookup returned HTTP $s_code (non-fatal)"
              fi
            else
              echo "ℹ No default space set — skipping space access check."
            fi

            # 3. CQL search reachability (v1, used for full-text search).
            cql_code=$(curl -sS -o /dev/null -w "%{http_code}" \\
                -u "$email:$token" \\
                -H "Accept: application/json" \\
                --get --data-urlencode "cql=type=page" --data-urlencode "limit=1" \\
                "$base/rest/api/search")
            if [ "$cql_code" = "200" ]; then
              echo "✓ CQL search endpoint reachable (/rest/api/search)"
            else
              echo "⚠ CQL search returned HTTP $cql_code (non-fatal)"
            fi

            echo ""
            echo "Token is valid — agent ready."
            exit 0
            """,
            successHint: "Token works against your Confluence site and the default space."
        ),
        bundledScripts: ["confluence.py"]
    )
}
