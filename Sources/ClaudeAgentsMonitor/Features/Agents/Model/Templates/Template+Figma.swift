import Foundation

extension AgentTemplate {
    static let figma = AgentTemplate(
        id: "figma",
        name: "figma",
        icon: "paintbrush.pointed.fill",
        assetIcon: "figma",
        color: "purple",
        description: "Figma design inspector: read files, frames, components, text, images, design tokens and variables via Figma REST API.",
        model: "sonnet",
        suggestedTools: [.Read, .Glob, .Grep, .WebFetch],
        bashPresetIds: ["curl / network read", "Read-only utils"],
        bashCategories: ["Network", "Files"],
        suggestedSkillNames: [],
        suggestedPluginIds: [],
        secretsToSetup: [
            SecretField(
                key: "FIGMA_API_TOKEN",
                label: "Figma Personal Access Token",
                placeholder: "figd_…",
                help: "Create at figma.com/settings → Personal access tokens. Needs at least 'File content' read scope. Works on any plan (Free/Pro/Org).",
                isOptional: false,
                providerIcon: "paintbrush.pointed.fill",
                providerColor: "purple",
                providerName: "Figma"
            )
        ],
        plainVarsToSetup: [
            PlainVarField(
                key: "FIGMA_DEFAULT_FILE_KEY",
                label: "Default file key",
                defaultValue: "",
                help: "Figma file key — the part of URL between /design/ or /file/ and the next /. E.g. for figma.com/design/AbCd123/My-Design → AbCd123. Leave empty if you work with many files.",
                isOptional: true
            ),
            PlainVarField(
                key: "FIGMA_DEFAULT_TEAM_ID",
                label: "Default team ID",
                defaultValue: "",
                help: "Team ID (numeric) — found in URL figma.com/files/team/<TEAM_ID>/... Leave empty to skip team-level operations.",
                isOptional: true
            )
        ],
        promptTemplate: """
        Ты — Figma design специалист. Работаешь через REST API v1.

        ## Основной путь — скрипт `figma.py` (используй в первую очередь)
        Готовый CLI: `.claude/agents/scripts/figma.py` (через `python3`). Токен из env `FIGMA_API_TOKEN`.
        **НЕ переписывай curl руками**, если задачу покрывает команда. FILE_KEY — из URL `figma.com/file/<KEY>/…`.
        ```
        python3 .claude/agents/scripts/figma.py file <FILE_KEY>          # имя + страницы
        python3 .claude/agents/scripts/figma.py node <FILE_KEY> 1:23     # дерево узла
        python3 .claude/agents/scripts/figma.py components <FILE_KEY>
        python3 .claude/agents/scripts/figma.py comments <FILE_KEY>
        python3 .claude/agents/scripts/figma.py image <FILE_KEY> 1:23 --format png
        ```
        `--json` к любой команде; `--help` — полный список. Если команды не хватает — HTTP fallback ниже.

        ## Авторизация
        Token в Keychain как `FIGMA_API_TOKEN`. Header: `X-Figma-Token: $FIGMA_API_TOKEN`. Никогда не печатай токен.

        ## HTTP cookbook (proven working — copy-paste ready)
        ```bash
        AUTH=( -H "X-Figma-Token: $FIGMA_API_TOKEN" -H "Accept: application/json" )
        BASE="https://api.figma.com/v1"
        ```

        ### Кто я
        ```bash
        curl -s "${AUTH[@]}" "$BASE/me" | jq -r '"\\(.handle) <\\(.email)> · \\(.id)"'
        ```

        ### File metadata + структура (frames, layers, components)
        ```bash
        FK="{FIGMA_DEFAULT_FILE_KEY}"
        curl -s "${AUTH[@]}" "$BASE/files/$FK?depth=2" | jq '{name, lastModified, version, document: .document.children[]?.name}'
        ```
        - `depth=1` — только страницы; `depth=2` — страницы + frames; без depth — весь tree (может быть мегабайты).

        ### Конкретный node (frame, component, instance)
        Node ID берётся из URL `…?node-id=123-456` → в API формат `123:456`.
        ```bash
        curl -s "${AUTH[@]}" "$BASE/files/$FK/nodes?ids=123:456&geometry=paths" \\
          | jq '.nodes["123:456"].document | {type, name, characters, absoluteBoundingBox, fills, strokes, effects}'
        ```

        ### Скачать изображения (PNG/SVG/PDF/JPG)
        ```bash
        # 1) Запросить генерацию
        urls=$(curl -s "${AUTH[@]}" "$BASE/images/$FK?ids=123:456&format=png&scale=2" | jq -r '.images | to_entries[] | "\\(.key)\\t\\(.value)"')
        # 2) Скачать каждый — это уже AWS S3 URL без auth
        echo "$urls" | while IFS=$'\\t' read id url; do
          curl -sL "$url" -o "/tmp/figma_${id//[:\\/]/_}.png"
        done
        ```
        После скачивания используй tool `Read` чтобы visually проанализировать PNG.

        ### Текст всех слоёв (для перевода / контент-аудита)
        ```bash
        curl -s "${AUTH[@]}" "$BASE/files/$FK" \\
          | jq -r '.. | objects | select(.type=="TEXT") | "\\(.id)\\t\\(.characters // "")"'
        ```

        ### Design tokens / Variables (новая variables API)
        ```bash
        curl -s "${AUTH[@]}" "$BASE/files/$FK/variables/local" \\
          | jq '.meta.variables[] | {name, resolvedType, valuesByMode}'
        ```
        Возвращает colors, numbers, strings, booleans с alias-chain. **Только Org plan** — на Free/Pro вернёт 403.

        ### Components / Component sets / Styles
        ```bash
        curl -s "${AUTH[@]}" "$BASE/files/$FK/components"  | jq '.meta.components[] | {key, name, description}'
        curl -s "${AUTH[@]}" "$BASE/files/$FK/styles"      | jq '.meta.styles[] | {key, name, style_type, description}'
        ```

        ### Comments на файле
        ```bash
        curl -s "${AUTH[@]}" "$BASE/files/$FK/comments" | jq '.comments[] | {message, user: .user.handle, resolved_at, client_meta}'
        ```

        ### Team-level (нужен TEAM_ID)
        ```bash
        TID="{FIGMA_DEFAULT_TEAM_ID}"
        curl -s "${AUTH[@]}" "$BASE/teams/$TID/projects"                                # все проекты команды
        curl -s "${AUTH[@]}" "$BASE/teams/$TID/components?page_size=30"                # published components
        curl -s "${AUTH[@]}" "$BASE/projects/<PROJECT_ID>/files"                       # файлы в проекте
        ```

        ## Готовые сценарии (русские триггеры)
        - `покажи структуру файла <KEY>` → `files/<KEY>?depth=2`
        - `вытащи дизайн-токены` → `files/<KEY>/variables/local` (Org plan) или `styles` (любой план)
        - `скриншот фрейма <NODE>` → `images/<KEY>?ids=<NODE>` → скачать → Read PNG → описать визуально
        - `сравни с реализацией` → скачать Figma image + скриншот реального UI (если есть Playwright MCP) → diff визуальный
        - `все тексты страницы <NODE>` → запросить node → `..|objects|select(.type=="TEXT")`
        - `компоненты файла` → `files/<KEY>/components`

        ## Парсинг URL Figma
        - `figma.com/design/<KEY>/...?node-id=<a>-<b>` → file_key=`<KEY>`, node_id=`<a>:<b>` (дефис → двоеточие!)
        - `figma.com/file/<KEY>/...` — legacy URL, тот же key
        - Старые URL также работают, API один.

        ## Правила
        - НЕ создавай/удаляй контент в Figma — этот template только для **чтения** (write endpoint comments-create поддержан, но требует явного разрешения).
        - При больших файлах (`depth` без ограничения) — используй `ids=…` чтобы загрузить только нужное.
        - Скачанные image-assets складывай в `/tmp/figma/` и удаляй после задачи.
        - Rate limit: ~50 req/min на токен. При 429 — backoff 60 сек.
        """,
        validation: TemplateValidation(
            label: "Verify Figma token + default file access",
            command: """
            token="{FIGMA_API_TOKEN}"
            fk="{FIGMA_DEFAULT_FILE_KEY}"
            tid="{FIGMA_DEFAULT_TEAM_ID}"

            token=$(printf '%s' "$token" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            fk=$(printf    '%s' "$fk"    | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            tid=$(printf   '%s' "$tid"   | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            if [ -z "$token" ]; then echo "✗ Token is required."; exit 1; fi

            # Token sanity. Figma PATs start with `figd_`.
            case "$token" in
              ghp_*|gho_*|github_pat_*|glpat-*|ATATT3*)
                echo "✗ This doesn't look like a Figma token (Figma PATs start with 'figd_')."
                exit 1 ;;
            esac

            echo "── /v1/me ──"
            tmp=$(mktemp)
            code=$(curl -sS -o "$tmp" -w "%{http_code}" --max-time 10 \\
                -H "X-Figma-Token: $token" -H "Accept: application/json" \\
                "https://api.figma.com/v1/me")
            body=$(cat "$tmp"); rm -f "$tmp"

            case "$code" in
              200)
                handle=$(echo "$body" | sed -n 's/.*"handle":"\\([^"]*\\)".*/\\1/p' | head -1)
                email=$(echo  "$body" | sed -n 's/.*"email":"\\([^"]*\\)".*/\\1/p'  | head -1)
                userId=$(echo "$body" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p'     | head -1)
                echo "✓ authenticated as $handle <$email> (id: $userId)"
                ;;
              401|403)
                echo "✗ Auth failed (HTTP $code). Re-create token at figma.com/settings → Personal access tokens."
                echo "$body" | head -3
                exit 1 ;;
              *)
                echo "✗ Unexpected HTTP $code from /v1/me"
                echo "$body" | head -3
                exit 1 ;;
            esac

            # Default file access (if provided).
            if [ -n "$fk" ]; then
              echo ""
              echo "── /v1/files/$fk ──"
              tmp=$(mktemp)
              code=$(curl -sS -o "$tmp" -w "%{http_code}" --max-time 15 \\
                  -H "X-Figma-Token: $token" -H "Accept: application/json" \\
                  "https://api.figma.com/v1/files/$fk?depth=1")
              body=$(cat "$tmp"); rm -f "$tmp"
              case "$code" in
                200)
                  fname=$(echo "$body" | sed -n 's/.*"name":"\\([^"]*\\)".*/\\1/p' | head -1)
                  modified=$(echo "$body" | sed -n 's/.*"lastModified":"\\([^"]*\\)".*/\\1/p' | head -1)
                  pages=$(echo "$body" | grep -o '"type":"CANVAS"' | wc -l | tr -d ' ')
                  echo "✓ '$fname' — $pages page(s), modified $modified"
                  ;;
                403)
                  echo "✗ Token has no access to file '$fk' (or file in another team)."
                  exit 1 ;;
                404)
                  echo "✗ File '$fk' not found. Re-check the key (the part between /design/ and the next /)."
                  exit 1 ;;
                *)
                  echo "⚠ Files endpoint returned HTTP $code (non-fatal — token still valid)" ;;
              esac
            else
              echo "ℹ No default file key — skipping file check."
            fi

            # Team-level access (if provided).
            if [ -n "$tid" ]; then
              echo ""
              echo "── /v1/teams/$tid/projects ──"
              code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \\
                  -H "X-Figma-Token: $token" -H "Accept: application/json" \\
                  "https://api.figma.com/v1/teams/$tid/projects")
              case "$code" in
                200) echo "✓ Team $tid is reachable" ;;
                403) echo "⚠ Token can't read team $tid (per-file access still works)" ;;
                404) echo "⚠ Team $tid not found" ;;
                *)   echo "⚠ Team endpoint returned HTTP $code" ;;
              esac
            fi

            echo ""
            echo "Token is valid — agent ready."
            exit 0
            """,
            successHint: "Figma PAT works and (if provided) the default file is reachable."
        ),
        bundledScripts: ["figma.py"]
    )
}
