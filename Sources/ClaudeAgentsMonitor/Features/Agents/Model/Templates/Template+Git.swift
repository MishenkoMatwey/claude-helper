import Foundation

extension AgentTemplate {
    static let git = AgentTemplate(
        id: "git",
        name: "git",
        icon: "arrow.triangle.branch",
        assetIcon: "git",
        color: "orange",
        description: "Git and GitHub specialist: branches, commits, PRs, conflicts and history across all local repositories.",
        model: "sonnet",
        suggestedTools: [.Read, .Glob, .Grep],
        bashPresetIds: ["Git safe edit", "Git push allowed", "GitHub CLI (gh)"],
        bashCategories: ["Git", "Files"],
        suggestedSkillNames: [],
        suggestedPluginIds: [
            "commit-commands@claude-plugins-official"
        ],
        secretsToSetup: [
            SecretField(
                key: "GITHUB_TOKEN",
                label: "GitHub Personal Access Token",
                placeholder: "ghp_…",
                help: "Create at github.com/settings/tokens — needs repo + read:org scopes. Leave empty if no GitHub remotes.",
                isOptional: true,
                providerIcon: "chevron.left.forwardslash.chevron.right",
                providerColor: "gray",
                providerName: "GitHub"
            ),
            SecretField(
                key: "GITLAB_TOKEN",
                label: "GitLab Personal Access Token",
                placeholder: "glpat-…",
                help: "Create at gitlab.com/-/user_settings/personal_access_tokens — needs api + read_repository scopes. Leave empty if no GitLab remotes.",
                isOptional: true,
                providerIcon: "fox",
                providerColor: "orange",
                providerName: "GitLab"
            )
        ],
        plainVarsToSetup: [
            PlainVarField(
                key: "PROJECTS_ROOT",
                label: "Projects directory",
                defaultValue: "",
                help: "Folder containing your git repos — agent will discover them automatically.",
                isFolder: true
            ),
            PlainVarField(
                key: "HOST",
                label: "Host",
                defaultValue: "",
                help: "Self-hosted host URL — e.g. https://gitlab.clussters.com or https://github.acme.com. Leave empty for github.com / gitlab.com.",
                isOptional: true
            )
        ],
        promptTemplate: """
        Ты — git/GitHub/GitLab специалист.

        ## Контекст
        - Работаешь с локальными репозиториями в `{PROJECTS_ROOT}`
        - Хостинг определяется по remote URL: `github.com` → GitHub, `gitlab.com` или self-hosted GitLab → GitLab
        - Токены в Keychain (см. Variables & Secrets ниже). Может быть только GitHub, только GitLab, или оба.

        ## CLI
        - **GitHub**: `gh` CLI — авторизуется через env `GH_TOKEN=$GITHUB_TOKEN`. Команды: `gh pr create`, `gh pr view`, `gh issue list`, `gh repo view`.
        - **GitLab**: `glab` CLI — авторизуется через env `GITLAB_TOKEN`. Команды: `glab mr create`, `glab mr view`, `glab issue list`. Если `glab` не установлен — fallback на REST: `curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" $GITLAB_HOST/api/v4/...`.

        ## Правила
        - НИКОГДА не делай `git push --force` в main/master без явного разрешения.
        - НИКОГДА не используй `--no-verify` или `--no-gpg-sign`.
        - Перед `reset --hard`, `branch -D`, force-push — спроси подтверждение.
        - Коммит-месседжи: смотри `git log` репо для стиля. Префикс `[CLS-XXX]` в проектах Clussters.
        - Конфликты резолвь, не выбрасывай чужие изменения.

        ## Поиск проектов
        - Список репозиториев: `find {PROJECTS_ROOT} -maxdepth 3 -type d -name ".git" -exec dirname {} \\;`
        - Активный текущий: `pwd` + `git rev-parse --is-inside-work-tree`
        - Хост текущего: `git remote get-url origin`

        ## MR/PR description format
        Тело через HEREDOC, в конце:
        ```
        🤖 Generated with [Claude Code](https://claude.com/claude-code)
        ```
        """,
        validation: TemplateValidation(
            label: "Verify GitHub token has access to your repos",
            command: """
            export GH_TOKEN="{GITHUB_TOKEN}"
            export GITLAB_TOKEN="{GITLAB_TOKEN}"
            HOST="{HOST}"
            HOST="${HOST%/}"
            root="{PROJECTS_ROOT}"

            # Resolve per-provider hosts.
            # If HOST is empty → public defaults. If set → use for whichever token is provided.
            if [ -n "$HOST" ]; then
              case "$HOST" in
                *github*) GH_HOST_URL="$HOST"; GITLAB_HOST="https://gitlab.com" ;;
                *gitlab*) GITLAB_HOST="$HOST"; GH_HOST_URL="https://api.github.com" ;;
                *) GH_HOST_URL="$HOST"; GITLAB_HOST="$HOST" ;;
              esac
            else
              GH_HOST_URL="https://api.github.com"
              GITLAB_HOST="https://gitlab.com"
            fi

            # Safety: refuse to scan home or root.
            case "$root" in
              "" | "/" | "$HOME" | "$HOME/")
                echo "✗ Refusing to scan $root — pick a specific project folder, not your home directory."
                exit 1
                ;;
            esac

            # At least one token must be provided.
            if [ -z "$GH_TOKEN" ] && [ -z "$GITLAB_TOKEN" ]; then
              echo "✗ Provide at least one token (GitHub or GitLab) — leave the unused one empty."
              exit 1
            fi

            # Token-format sanity check: GitLab tokens start with glpat-, GitHub tokens start with ghp_, gho_, github_pat_, or are PAT v2.
            if [ -n "$GH_TOKEN" ]; then
              case "$GH_TOKEN" in
                glpat-*)
                  echo "✗ The value in 'GitHub' field looks like a GitLab token (glpat-…). Move it to the GitLab field."
                  exit 1 ;;
              esac
            fi
            if [ -n "$GITLAB_TOKEN" ]; then
              case "$GITLAB_TOKEN" in
                ghp_*|gho_*|github_pat_*)
                  echo "✗ The value in 'GitLab' field looks like a GitHub token. Move it to the GitHub field."
                  exit 1 ;;
              esac
            fi

            # 1. Validate GitHub token (if provided).
            gh_ok=0
            if [ -n "$GH_TOKEN" ]; then
              if ! command -v gh >/dev/null 2>&1; then
                echo "✗ 'gh' CLI not found. Install: brew install gh"
                exit 1
              fi
              # For GH Enterprise: `gh` reads GH_HOST as bare host (no scheme).
              if [ "$GH_HOST_URL" != "https://api.github.com" ]; then
                export GH_HOST=$(echo "$GH_HOST_URL" | sed -E 's|^https?://||; s|/$||')
              fi
              user_json=$(gh api user 2>&1)
              if [ $? -ne 0 ]; then
                echo "✗ GitHub token is invalid on $GH_HOST_URL:"
                echo "$user_json" | head -3
                exit 1
              fi
              gh_login=$(echo "$user_json" | sed -n 's/.*"login":"\\([^"]*\\)".*/\\1/p')
              echo "✓ GitHub: authenticated as $gh_login on $GH_HOST_URL"
              gh_ok=1
            else
              echo "ℹ GitHub token not provided — skipping GitHub checks."
            fi

            # 2. Validate GitLab token (if provided).
            gl_ok=0
            if [ -n "$GITLAB_TOKEN" ]; then
              gl_json=$(curl -sS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" $GITLAB_HOST/api/v4/user)
              if echo "$gl_json" | grep -q '"username"'; then
                gl_login=$(echo "$gl_json" | sed -n 's/.*"username":"\\([^"]*\\)".*/\\1/p')
                echo "✓ GitLab: authenticated as $gl_login"
                gl_ok=1
              else
                echo "✗ GitLab token is invalid:"
                echo "$gl_json" | head -3
                exit 1
              fi
            else
              echo "ℹ GitLab token not provided — skipping GitLab checks."
            fi

            # 3. Scan repos under root.
            mapfile -t gitdirs < <(find "$root" -maxdepth 4 \\
                \\( -name node_modules -o -name .build -o -name target -o \\
                   -name Library -o -name Music -o -name Pictures -o \\
                   -name Movies -o -name .Trash -o -name DerivedData \\) -prune -o \\
                -type d -name ".git" -print 2>/dev/null)

            total=${#gitdirs[@]}
            if [ "$total" -eq 0 ]; then
              echo ""
              echo "ℹ No git repositories under $root yet. Token(s) are valid — agent ready."
              exit 0
            fi
            echo ""
            echo "Found $total git repo(s) in $root"

            # 4. Per-repo access check by host.
            gh_checked=0; gh_ok_count=0; gh_denied=()
            gl_checked=0; gl_ok_count=0; gl_denied=()
            other=0
            for gitdir in "${gitdirs[@]}"; do
              repo=$(dirname "$gitdir")
              remote=$(cd "$repo" && git remote get-url origin 2>/dev/null)
              [ -z "$remote" ] && continue
              slug=$(echo "$remote" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\\1|; s|\\.git$||')
              case "$remote" in
                *github.com*)
                  if [ "$gh_ok" -eq 1 ]; then
                    gh_checked=$((gh_checked+1))
                    if gh repo view "$slug" --json name >/dev/null 2>&1; then
                      gh_ok_count=$((gh_ok_count+1))
                    else
                      gh_denied+=("$slug")
                    fi
                  fi ;;
                *gitlab.com*|*gitlab*)
                  if [ "$gl_ok" -eq 1 ]; then
                    gl_checked=$((gl_checked+1))
                    # URL-encode the slug for the API path.
                    encoded=$(printf '%s' "$slug" | sed 's|/|%2F|g')
                    if curl -sSf -o /dev/null --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \\
                       "$GITLAB_HOST/api/v4/projects/$encoded"; then
                      gl_ok_count=$((gl_ok_count+1))
                    else
                      gl_denied+=("$slug")
                    fi
                  fi ;;
                *) other=$((other+1)) ;;
              esac
            done

            if [ "$gh_checked" -gt 0 ]; then
              echo "GitHub: $gh_ok_count / $gh_checked accessible"
              [ "${#gh_denied[@]}" -gt 0 ] && printf "  ✗ %s\\n" "${gh_denied[@]}"
            fi
            if [ "$gl_checked" -gt 0 ]; then
              echo "GitLab: $gl_ok_count / $gl_checked accessible"
              [ "${#gl_denied[@]}" -gt 0 ] && printf "  ✗ %s\\n" "${gl_denied[@]}"
            fi
            [ "$other" -gt 0 ] && echo "Other hosts (skipped): $other"
            echo ""
            echo "ℹ Inaccessible repos are OK if you don't need to operate on them. Token(s) are valid."
            exit 0
            """,
            successHint: "Token works for all repos found in projects directory."
        )
    )
}
