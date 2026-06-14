import Foundation

private let dbSchemes = ["postgres", "mysql", "clickhouse", "mssql", "sqlite"]

/// Runs after agent save to materialise a `references/db-schema.md` file with full DB structure
/// (schemas, tables, columns, primary keys, foreign keys). Lives OUTSIDE `agents/` so that
/// the 100K+ file doesn't get auto-pulled into the agent's prompt — the agent greps it on demand.
private let dbPostCreateCommand = """
OUT="{AGENT_DIR}/../references/db-schema.md"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

ts=$(date "+%Y-%m-%d %H:%M:%S")
printf '# Schema map — {AGENT_NAME}\\n_Auto-generated %s. Re-run by deleting this file._\\n\\n' "$ts" >> "$OUT"

introspect_pg() {
  local alias="$1" host="$2" port="$3" user="$4" pass="$5" db="$6"
  echo "→ postgres: ${alias} / ${db}"
  export PGPASSWORD="$pass" PGCONNECT_TIMEOUT=10
  local args=( -h "$host" -p "$port" -U "$user" -d "$db" -A -F$'\\t' -t -w )

  if ! psql "${args[@]}" -c "SELECT 1" >/dev/null 2>&1; then
    printf '> ⚠ Skipped `%s/%s` — connect failed.\\n\\n' "$alias" "$db" >> "$OUT"
    return
  fi

  printf '## %s · %s (postgres)\\n\\n' "$alias" "$db" >> "$OUT"

  # Tables + estimated row counts
  printf '### Tables\\n\\n' >> "$OUT"
  psql "${args[@]}" -c "
    SELECT n.nspname, c.relname, c.reltuples::bigint
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE c.relkind IN ('r','p')
       AND n.nspname NOT IN ('pg_catalog','information_schema')
       AND n.nspname NOT LIKE 'pg_%'
     ORDER BY n.nspname, c.relname" 2>/dev/null \\
    | awk -F'\\t' 'BEGIN{print "| schema | table | ≈ rows |"; print "|---|---|---|"}
                   NF>=3 {printf "| %s | %s | %s |\\n", $1, $2, $3}' >> "$OUT"
  printf '\\n' >> "$OUT"

  # Columns
  printf '### Columns\\n\\n' >> "$OUT"
  psql "${args[@]}" -c "
    SELECT table_schema, table_name, column_name, data_type, is_nullable, COALESCE(column_default,'')
      FROM information_schema.columns
     WHERE table_schema NOT IN ('pg_catalog','information_schema')
       AND table_schema NOT LIKE 'pg_%'
     ORDER BY table_schema, table_name, ordinal_position" 2>/dev/null \\
    | awk -F'\\t' 'BEGIN{prev=""}
        NF>=6 {key=$1"."$2;
               if(key!=prev){printf "\\n**%s.%s**\\n\\n", $1, $2;
                              print "| column | type | nullable | default |";
                              print "|---|---|---|---|"; prev=key}
               printf "| %s | %s | %s | %s |\\n", $3, $4, $5, $6}' >> "$OUT"
  printf '\\n' >> "$OUT"

  # Primary keys
  printf '### Primary keys\\n\\n' >> "$OUT"
  psql "${args[@]}" -c "
    SELECT kcu.table_schema, kcu.table_name, string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position)
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name=kcu.constraint_name AND tc.table_schema=kcu.table_schema
     WHERE tc.constraint_type='PRIMARY KEY'
       AND tc.table_schema NOT IN ('pg_catalog','information_schema')
     GROUP BY 1,2 ORDER BY 1,2" 2>/dev/null \\
    | awk -F'\\t' 'NF>=3 {printf "- `%s.%s` → %s\\n", $1, $2, $3}' >> "$OUT"
  printf '\\n' >> "$OUT"

  # Foreign keys
  printf '### Foreign keys\\n\\n' >> "$OUT"
  psql "${args[@]}" -c "
    SELECT kcu.table_schema, kcu.table_name, kcu.column_name,
           ccu.table_schema, ccu.table_name, ccu.column_name
      FROM information_schema.referential_constraints r
      JOIN information_schema.key_column_usage kcu
        ON kcu.constraint_name=r.constraint_name
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name=r.unique_constraint_name
     WHERE kcu.table_schema NOT IN ('pg_catalog','information_schema')
     ORDER BY kcu.table_schema, kcu.table_name, kcu.column_name" 2>/dev/null \\
    | awk -F'\\t' 'NF>=6 {printf "- `%s.%s.%s` → `%s.%s.%s`\\n", $1, $2, $3, $4, $5, $6}' >> "$OUT"
  printf '\\n' >> "$OUT"

  # Indexes (compact list)
  printf '### Indexes\\n\\n' >> "$OUT"
  psql "${args[@]}" -c "
    SELECT schemaname, tablename, indexname, indexdef
      FROM pg_indexes
     WHERE schemaname NOT IN ('pg_catalog','information_schema')
     ORDER BY schemaname, tablename, indexname" 2>/dev/null \\
    | awk -F'\\t' 'NF>=4 {gsub(/`/,"",$4); printf "- `%s.%s`: %s\\n", $1, $2, $3}' >> "$OUT"
  printf '\\n---\\n\\n' >> "$OUT"
}

introspect_slot() {
  local slot="$1"
  local scheme=$(eval "printf '%s' \\"\\${DB${slot}_SCHEME:-}\\"")
  local host_raw=$(eval "printf '%s' \\"\\${DB${slot}_HOST:-}\\"")
  local user=$(eval    "printf '%s' \\"\\${DB${slot}_USER:-}\\"")
  local pass=$(eval    "printf '%s' \\"\\${DB${slot}_PASSWORD:-}\\"")
  local dbs=$(eval     "printf '%s' \\"\\${DB${slot}_DATABASE:-}\\"")
  local alias=$(eval   "printf '%s' \\"\\${DB${slot}_ALIAS:-}\\"")
  [ -z "$host_raw" ] && return

  local host=$(printf '%s' "$host_raw" | awk -F':' '{print $1}')
  local port=$(printf '%s' "$host_raw" | awk -F':' '{print $2}' | tr -cd '0-9')
  [ -z "$port" ] && {
    case "$scheme" in
      postgres|postgresql) port=5432 ;;
      mysql|mariadb)       port=3306 ;;
      clickhouse)          port=8123 ;;
      mssql|sqlserver)     port=1433 ;;
    esac
  }

  case "$scheme" in
    postgres|postgresql)
      if ! command -v psql >/dev/null 2>&1; then
        printf '> ⚠ Skipped slot %s (%s) — psql not installed.\\n\\n' "$slot" "$alias" >> "$OUT"
        return
      fi
      IFS=',' read -ra DB_LIST <<< "$dbs"
      for raw in "${DB_LIST[@]}"; do
        db=$(printf '%s' "$raw" | xargs)
        [ -z "$db" ] && continue
        introspect_pg "$alias" "$host" "$port" "$user" "$pass" "$db"
      done ;;
    *)
      printf '> ℹ Slot %s (%s, %s): introspection not implemented yet — agent can describe via SHOW/DESCRIBE on demand.\\n\\n' \\
        "$slot" "$alias" "$scheme" >> "$OUT" ;;
  esac
}

# Pull slot values from this script's env (TemplateAgentSheet exports them just before exec).
export DB1_ALIAS="{DB1_ALIAS}" DB1_SCHEME="{DB1_SCHEME}" DB1_HOST="{DB1_HOST}" DB1_USER="{DB1_USER}" DB1_PASSWORD="{DB1_PASSWORD}" DB1_DATABASE="{DB1_DATABASE}"
export DB2_ALIAS="{DB2_ALIAS}" DB2_SCHEME="{DB2_SCHEME}" DB2_HOST="{DB2_HOST}" DB2_USER="{DB2_USER}" DB2_PASSWORD="{DB2_PASSWORD}" DB2_DATABASE="{DB2_DATABASE}"
export DB3_ALIAS="{DB3_ALIAS}" DB3_SCHEME="{DB3_SCHEME}" DB3_HOST="{DB3_HOST}" DB3_USER="{DB3_USER}" DB3_PASSWORD="{DB3_PASSWORD}" DB3_DATABASE="{DB3_DATABASE}"
export DB4_ALIAS="{DB4_ALIAS}" DB4_SCHEME="{DB4_SCHEME}" DB4_HOST="{DB4_HOST}" DB4_USER="{DB4_USER}" DB4_PASSWORD="{DB4_PASSWORD}" DB4_DATABASE="{DB4_DATABASE}"
export DB5_ALIAS="{DB5_ALIAS}" DB5_SCHEME="{DB5_SCHEME}" DB5_HOST="{DB5_HOST}" DB5_USER="{DB5_USER}" DB5_PASSWORD="{DB5_PASSWORD}" DB5_DATABASE="{DB5_DATABASE}"

for slot in 1 2 3 4 5; do
  introspect_slot "$slot"
done

bytes=$(wc -c < "$OUT" | tr -d ' ')
echo ""
echo "✓ Schema map written → $OUT ($bytes bytes)"
"""


/// Per-slot verify command. Placeholders `{ALIAS}`, `{SCHEME}`, `{HOST}`, `{USER}`, `{PASSWORD}`, `{DATABASE}`
/// are substituted by TemplateAgentSheet before exec.
private let dbVerifyCommand = """
ALIAS="{ALIAS}"
SCHEME="{SCHEME}"
HOST_RAW="{HOST}"
USER="{USER}"
PASS="{PASSWORD}"
DB="{DATABASE}"

# Strip whitespace defensively.
trim() { printf '%s' "$1" | tr -d '\\r\\n\\t' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
ALIAS=$(trim "$ALIAS")
SCHEME=$(trim "$SCHEME")
HOST_RAW=$(trim "$HOST_RAW")
USER=$(trim "$USER")
DB=$(trim "$DB")

if [ -z "$SCHEME" ]; then echo "✗ Scheme is empty — pick one."; exit 1; fi
SCHEME=$(printf '%s' "$SCHEME" | tr '[:upper:]' '[:lower:]')

# Split host:port — sqlite uses path in HOST.
HOST=$(printf '%s' "$HOST_RAW" | awk -F':' '{print $1}')
PORT=$(printf '%s' "$HOST_RAW" | awk -F':' '{print $2}' | tr -cd '0-9')
case "$SCHEME" in
  postgres|postgresql) [ -z "$PORT" ] && PORT=5432 ;;
  mysql|mariadb)       [ -z "$PORT" ] && PORT=3306 ;;
  clickhouse)          [ -z "$PORT" ] && PORT=8123 ;;
  mssql|sqlserver)     [ -z "$PORT" ] && PORT=1433 ;;
  sqlite)              : ;;
  *) echo "✗ Unsupported scheme '$SCHEME'. Use one of: ${dbSchemes_csv}"; exit 1 ;;
esac

mask_pass=$([ -n "$PASS" ] && echo "***" || echo "<empty>")
echo "── ${ALIAS:-(no-alias)} ──"
echo "  scheme:   $SCHEME"
echo "  host:     ${HOST:-(none)}"
echo "  port:     ${PORT:-(none)}"
echo "  user:     ${USER:-(none)}"
echo "  database: ${DB:-(none)}"
echo "  password: $mask_pass (${#PASS} chars)"
echo ""

# SQLite — file check.
# Multi-DB support: take the first DB from a comma-separated list for the probe.
PRIMARY_DB=$(printf '%s' "$DB" | awk -F',' '{gsub(/^[ \\t]+|[ \\t]+$/, "", $1); print $1}')
ALL_DBS=$(printf '%s' "$DB" | awk -F',' '{for(i=1;i<=NF;i++){gsub(/^[ \\t]+|[ \\t]+$/, "", $i); printf "%s%s", $i, (i<NF ? ", " : "")}}')
DB_COUNT=$(printf '%s' "$DB" | awk -F',' '{n=0; for(i=1;i<=NF;i++){gsub(/[ \\t]/, "", $i); if(length($i)) n++} print n}')

if [ "$DB_COUNT" -gt 1 ]; then
  echo "  databases: $ALL_DBS  (probe will use $PRIMARY_DB)"
fi

if [ "$SCHEME" = "sqlite" ]; then
  path="$HOST_RAW"
  [ -z "$path" ] && path="$PRIMARY_DB"
  if [ -z "$path" ]; then echo "✗ Provide absolute file path in Host or DB field."; exit 1; fi
  if [ ! -f "$path" ]; then echo "✗ File not found: $path"; exit 1; fi
  if command -v sqlite3 >/dev/null 2>&1; then
    if sqlite3 "$path" "SELECT 1" >/dev/null 2>&1; then echo "✓ sqlite3 SELECT 1 ok"; exit 0
    else echo "✗ sqlite3 SELECT 1 failed"; exit 1; fi
  else
    echo "ℹ sqlite3 CLI missing — file exists, agent can install (built-in on macOS by default)."
    exit 0
  fi
fi

if [ -z "$HOST" ] || [ -z "$PORT" ]; then echo "✗ Host or port missing."; exit 1; fi

# TCP-check: try nc (BSD on macOS, GNU on Linux), then bash /dev/tcp as last resort.
# `timeout` from GNU coreutils is NOT pre-installed on macOS — avoid it.
tcp_ok=0
if command -v nc >/dev/null 2>&1; then
  # BSD nc: -G <sec> = connect timeout. GNU nc: -w <sec>. Try both.
  if nc -z -G 5 "$HOST" "$PORT" >/dev/null 2>&1 \
     || nc -z -w 5 "$HOST" "$PORT" >/dev/null 2>&1; then
    tcp_ok=1
  fi
elif command -v perl >/dev/null 2>&1; then
  if perl -MIO::Socket::INET -e 'exit !defined IO::Socket::INET->new(PeerAddr=>$ARGV[0],PeerPort=>$ARGV[1],Timeout=>5)' "$HOST" "$PORT" 2>/dev/null; then
    tcp_ok=1
  fi
else
  # Bash /dev/tcp builtin — fast when reachable, but hangs on dropped firewalls. Run in a
  # background subshell and kill after 5s so we never get stuck.
  ( bash -c ">/dev/tcp/$HOST/$PORT" 2>/dev/null ) &
  bg=$!
  ( sleep 5 && kill -9 "$bg" 2>/dev/null ) &
  killer=$!
  if wait "$bg" 2>/dev/null; then tcp_ok=1; fi
  kill "$killer" 2>/dev/null
fi

if [ "$tcp_ok" -eq 1 ]; then
  echo "✓ TCP $HOST:$PORT reachable"
else
  echo "✗ TCP $HOST:$PORT not reachable (firewall / VPN / wrong port?)"
  exit 1
fi

# Deep check via CLI when available; otherwise pass on TCP.
discover_emit() {
  # $1 — newline-separated DB names. Emit marker the UI parses.
  local raw="$1"
  local csv
  csv=$(printf '%s' "$raw" | tr -d '\\r' | sed '/^$/d' | paste -sd, -)
  if [ -n "$csv" ]; then echo "DATABASES_DISCOVERED: $csv"; fi
}

case "$SCHEME" in
  postgres|postgresql)
    if command -v psql >/dev/null 2>&1; then
      # Use individual flags (not URL) — avoids psql URL-parser quirks with extra colons.
      export PGPASSWORD="$PASS" PGCONNECT_TIMEOUT=5
      PSQL_ARGS=( -h "$HOST" -p "$PORT" -U "$USER" -d "$PRIMARY_DB" -A -t -w )
      if out=$(psql "${PSQL_ARGS[@]}" -c "SELECT 1" 2>&1); then
        echo "✓ psql SELECT 1 → $out"
        list=$(psql "${PSQL_ARGS[@]}" -c \
          "SELECT datname FROM pg_database \
             WHERE datistemplate=false AND datallowconn \
               AND has_database_privilege(current_user, datname, 'CONNECT') \
           ORDER BY datname" 2>/dev/null)
        if [ -n "$list" ]; then
          echo ""
          echo "Visible databases on this host:"
          printf '  • %s\\n' $list
          discover_emit "$list"
        fi
      else
        echo "✗ psql failed:"; echo "  $out" | head -5; exit 1
      fi
    else
      echo "ℹ psql not installed (brew install libpq && brew link --force libpq) — TCP ok, skipping deep check."
    fi ;;
  mysql|mariadb)
    if command -v mysql >/dev/null 2>&1; then
      if out=$(MYSQL_PWD="$PASS" mysql --connect-timeout=5 -h "$HOST" -P "$PORT" -u "$USER" -D "$PRIMARY_DB" -BNe "SELECT 1" 2>&1); then
        echo "✓ mysql SELECT 1 → $out"
        list=$(MYSQL_PWD="$PASS" mysql --connect-timeout=5 -h "$HOST" -P "$PORT" -u "$USER" -BNe "SHOW DATABASES" 2>/dev/null \
          | grep -Ev '^(information_schema|performance_schema|mysql|sys)$')
        if [ -n "$list" ]; then
          echo ""
          echo "Visible databases on this host:"
          printf '  • %s\\n' $list
          discover_emit "$list"
        fi
      else
        echo "✗ mysql failed:"; echo "  $out" | head -5; exit 1
      fi
    else
      echo "ℹ mysql CLI not installed (brew install mysql-client) — TCP ok."
    fi ;;
  clickhouse)
    HTTP_URL="http://${HOST}:${PORT}"
    if [ -n "$PASS" ]; then AUTH=( -u "${USER}:${PASS}" ); else AUTH=( -u "${USER}:" ); fi
    if out=$(curl -fsS --max-time 5 "${AUTH[@]}" --get --data-urlencode "query=SELECT 1" "$HTTP_URL/" 2>&1); then
      echo "✓ ClickHouse HTTP SELECT 1 → $(printf '%s' "$out" | head -1)"
      list=$(curl -fsS --max-time 5 "${AUTH[@]}" --get \
        --data-urlencode "query=SELECT name FROM system.databases WHERE name NOT IN ('system','INFORMATION_SCHEMA','information_schema') FORMAT TabSeparated" \
        "$HTTP_URL/" 2>/dev/null)
      if [ -n "$list" ]; then
        echo ""
        echo "Visible databases on this host:"
        printf '  • %s\\n' $list
        discover_emit "$list"
      fi
    else
      echo "⚠ HTTP probe failed (CH native 9000? wrong port?) — TCP ok, deep check inconclusive."
    fi ;;
  mssql|sqlserver)
    if command -v sqlcmd >/dev/null 2>&1; then
      if out=$(sqlcmd -l 5 -S "${HOST},${PORT}" -U "$USER" -P "$PASS" -d "$PRIMARY_DB" -Q "SELECT 1" 2>&1); then
        echo "✓ sqlcmd SELECT 1 ok"
        list=$(sqlcmd -l 5 -S "${HOST},${PORT}" -U "$USER" -P "$PASS" -d "$PRIMARY_DB" -h -1 -W -Q \
          "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name" 2>/dev/null \
          | tr -d '\\r' | sed '/^$/d')
        if [ -n "$list" ]; then
          echo ""
          echo "Visible databases on this host:"
          printf '  • %s\\n' $list
          discover_emit "$list"
        fi
      else
        echo "✗ sqlcmd failed:"; echo "  $out" | head -5; exit 1
      fi
    else
      echo "ℹ sqlcmd not installed (brew tap microsoft/mssql-release && brew install mssql-tools18) — TCP ok."
    fi ;;
esac

exit 0
"""

private func dbConnection(slot: Int, optional: Bool) -> ConnectionField {
    let p = "DB\(slot)"
    return ConnectionField(
        slotId: p,
        title: "Connection #\(slot)",
        isOptional: optional,
        aliasKey: "\(p)_ALIAS",
        schemeKey: "\(p)_SCHEME",
        schemeOptions: dbSchemes,
        hostKey: "\(p)_HOST",
        userKey: "\(p)_USER",
        passwordKey: "\(p)_PASSWORD",
        databaseKey: "\(p)_DATABASE",
        verifyCommand: dbVerifyCommand.replacingOccurrences(
            of: "${dbSchemes_csv}", with: dbSchemes.joined(separator: ", ")
        )
    )
}

extension AgentTemplate {
    static let database = AgentTemplate(
        id: "database",
        name: "db-readonly",
        icon: "cylinder.split.1x2.fill",
        assetIcon: nil,
        color: "blue",
        description: "READ-ONLY SQL agent across multiple databases (Postgres / MySQL / ClickHouse / MSSQL / SQLite). Verifies every connection independently. Never executes write/DDL statements.",
        model: "sonnet",
        suggestedTools: [.Read, .Glob, .Grep],
        bashPresetIds: ["psql (read)", "mysql (read)", "Read-only utils", "Search utils"],
        bashCategories: ["Databases", "Files"],
        suggestedSkillNames: [],
        suggestedPluginIds: [],
        secretsToSetup: [],
        plainVarsToSetup: [],
        promptTemplate: """
        Ты — read-only SQL агент. У тебя несколько подключений; для каждого в env есть набор переменных.

        ## Быстрый доступ — скрипт `db.py` (postgres, принудительно read-only)
        Для postgres-слотов используй `.claude/agents/scripts/db.py` (через `python3`): он **сам отклоняет любые не-SELECT**, ставит statement_timeout и лимит строк — безопаснее, чем сырой psql. Маппь слот `DB<N>_*` в стандартные `PG*`-переменные:
        ```bash
        host="${DB1_HOST%%:*}"; port="${DB1_HOST##*:}"; [ "$port" = "$host" ] && port=6432
        IFS=',' read -r db _ <<< "$DB1_DATABASE"; db=$(echo "$db" | xargs)   # первая база из списка
        PGHOST="$host" PGPORT="$port" PGUSER="$DB1_USER" PGPASSWORD="$DB1_PASSWORD" PGDATABASE="$db" \\
          python3 .claude/agents/scripts/db.py tables
        ```
        Команды: `databases` · `tables [--schema public]` · `schema <table>` · `sample <table>` · `count <table>` · `query "<SELECT…>"`. `--json` для машинного вывода.

        ### Несколько БД на одном хосте
        `DB<N>_DATABASE` — это **список баз через запятую** (один host/user/password ко всем). Не нужно переэкспортировать env под каждую — используй флаг `--db <name>`:
        ```bash
        python3 .claude/agents/scripts/db.py databases                 # все базы хоста
        python3 .claude/agents/scripts/db.py --db portfolio tables     # конкретная база
        # перебрать все базы из списка:
        IFS=',' read -ra DBS <<< "$DB1_DATABASE"
        for raw in "${DBS[@]}"; do d=$(echo "$raw" | xargs); echo "== $d =="; python3 .claude/agents/scripts/db.py --db "$d" tables; done
        ```
        Если задача про конкретную базу — бери её через `--db`; если «во всех» — перебирай список. Полная карта схем — в `references/db-schema.md` (грепай, не читай целиком).
        Для **не-postgres** (mysql/clickhouse/mssql/sqlite) — нативный клиент/psql как описано ниже.

        ## Карта БД (не читай целиком!)

        Полная карта схем лежит в `<project>/.claude/references/db-schema.md` (190K+ символов, ~63k токенов). **Никогда не делай `Read` этого файла целиком.** Доставай только то, что нужно по задаче:
        - Таблица по имени: `grep -n -A 30 "CREATE TABLE.* <table>" .../references/db-schema.md`
        - Все FK на таблицу: `grep -B 5 "REFERENCES <table>" .../references/db-schema.md`
        - Поиск по фрагменту имени: `grep -n -i "<frag>" .../references/db-schema.md | head -50`

        Если файл устарел/пуст или пользователь явно сказал "обнови схему" — удали файл, и при следующем запуске monitor пересоберёт его.


        ```
        DB<N>_ALIAS      — короткое имя (например "main", "analytics")
        DB<N>_SCHEME     — postgres | mysql | clickhouse | mssql | sqlite
        DB<N>_HOST       — host[:port]  (для sqlite — путь к файлу)
        DB<N>_USER       — логин
        DB<N>_PASSWORD   — пароль (Keychain → env, никогда не печатай)
        DB<N>_DATABASE   — имя базы
        ```

        N=1..5. Сначала проверь `[ -n "$DB<N>_HOST" ]` чтобы понять какие слоты заполнены.

        ## Несколько БД на одном хосте
        Поле `DB<N>_DATABASE` — это **comma-separated список** баз (`db1, db2, db3`). Один host/user/password подключается ко всем.

        Парсинг списка (bash):
        ```bash
        IFS=',' read -ra DBS <<< "$DB1_DATABASE"
        for raw in "${DBS[@]}"; do
          db=$(echo "$raw" | xargs)   # trim spaces
          PGPASSWORD="$DB1_PASSWORD" psql -h "$DB1_HOST" -U "$DB1_USER" -d "$db" -c "..."
        done
        ```

        Переключение в одной psql-сессии: `\\c <db>`.
        В mysql: `USE <db>;`.
        ClickHouse: указывай БД в запросе через `<db>.<table>` или параметр `database=<db>`.

        Если пользователь сказал "по базе X" — найди X в `DB<N>_DATABASE`-листе соответствующего alias.

        ## Сборка connection string (одна БД)
        - **postgres/mysql/mssql**: `<scheme>://$DB<N>_USER:$DB<N>_PASSWORD@$DB<N>_HOST/<db>`
        - **clickhouse HTTP**: `http://$DB<N>_HOST` + Basic auth `-u $DB<N>_USER:$DB<N>_PASSWORD` + `?database=<db>`
        - **sqlite**: `$DB<N>_HOST` — это путь к файлу

        ## CLI
        | Scheme       | Команда                                                          |
        |--------------|------------------------------------------------------------------|
        | postgres     | `psql "$URL" -A -t -c "SELECT 1"`                                |
        | mysql        | `MYSQL_PWD=$PASS mysql -h $HOST -u $USER -D $DB -BNe "SELECT 1"` |
        | clickhouse   | `curl -u $USER:$PASS "http://$HOST/?query=SELECT+1"`              |
        | mssql        | `sqlcmd -S "$HOST,$PORT" -U "$USER" -P "$PASS" -Q "SELECT 1"`     |
        | sqlite       | `sqlite3 "$PATH" "SELECT 1"`                                     |

        ## STRICT READ-ONLY
        - НИКОГДА `INSERT / UPDATE / DELETE / TRUNCATE / DROP / ALTER / CREATE / GRANT / REVOKE`.
        - Postgres: начинай сессию `SET TRANSACTION READ ONLY;`
        - MySQL: `SET SESSION TRANSACTION READ ONLY;`
        - Дефолтный `LIMIT 100` для exploratory.
        - Маскируй пароли при упоминании DSN: `postgres://user:***@host/db`.

        ## Discovery
        - Postgres: `\\dt` или `SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1,2;`
        - MySQL/ClickHouse: `SHOW TABLES;` · `DESCRIBE <table>;`
        - MSSQL: `SELECT name FROM sys.tables;`
        - SQLite: `.tables` или `SELECT name FROM sqlite_master WHERE type='table';`

        ## Когда пользователь говорит "из базы X" — мэтчи на `DB<N>_ALIAS`. Если alias неоднозначен — переспроси.
        """,
        validation: nil,
        connections: [
            dbConnection(slot: 1, optional: false),
            dbConnection(slot: 2, optional: true),
            dbConnection(slot: 3, optional: true),
            dbConnection(slot: 4, optional: true),
            dbConnection(slot: 5, optional: true)
        ],
        postCreateCommand: dbPostCreateCommand,
        postCreateLabel: "Discovering schema, tables, relations…",
        bundledScripts: ["db.py"]
    )
}
