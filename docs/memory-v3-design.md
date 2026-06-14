# Память агентов v3 — дизайн

Документ описывает новую систему памяти CAM: SQLite-хранилище со связями,
RAG-поиск для агента и граф-вью для человека. Перед кодом — чтобы согласовать форму.

## Зачем (проблемы текущей v2)

Сейчас память — markdown-файлы (`compiled.md` / `log.md`), и это «криво»:

1. **Два компилятора** (`tools/compile-memory.py` + `MemoryCompilerService.swift`) — дрейф.
2. **Двойное хранение** — данные в source-файлах И в `compiled.md`, рассинхрон.
3. **`log.md` растёт бесконечно** — агенту говорят «не читай целиком», ротации нет.
4. **Память плоская** — нет связей, нет дедупликации, нет переиспользования.
5. **Держится на дисциплине LLM** — забыл записать → память сгнила.

Цель v3:
- агент **помнит прошлые сессии** и **сам обновляет** память (через инструменты, не дисциплину);
- **читает только релевантное** (RAG-retrieval, не дамп всего контекста);
- человек видит **нормальный UI** (граф связей, поиск, редактор), а не кучу файлов.

## Хранилище

**SQLite, один файл на проект.** Реальная БД, но embedded — без сервера.

```
<project>/.claude/agents/memory/memory.db        # БД (per-project)
~/.claude/agents/memory/memory.db                # global (User)
```

Через `AgentPaths` добавляем:

```swift
extension AgentPaths {
    var memoryDBFile: URL { memoryDir.appendingPathComponent("memory.db") }
}
```

Доступ из Swift — **GRDB** (добавляем в `Package.swift`). GRDB даёт типизированный
доступ + наблюдение за изменениями (`ValueObservation`) → SwiftUI граф-вью обновляется живьём.

> В проекте уже есть референс-схема в `.swarm/memory.db` (RuFlo V3) — берём идеи
> (типы заметок, decay, namespace), но реализуем свой компактный слой на GRDB.

## Схема БД

Три таблицы. Граф — это таблица `edges`, отдельная graph-БД не нужна.

```sql
-- Одна заметка = один факт/правило/событие
CREATE TABLE notes (
  id          TEXT PRIMARY KEY,         -- nanoid
  agent       TEXT NOT NULL,            -- к какому агенту относится ('' = shared между всеми)
  kind        TEXT NOT NULL,            -- fact | rule | playbook | session | var
  title       TEXT NOT NULL,            -- короткий заголовок (для UI и поиска)
  body        TEXT NOT NULL,            -- содержимое
  tags        TEXT,                     -- JSON-массив строк
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  last_used_at INTEGER,                 -- когда последний раз попал в выдачу (decay/hot-cold)
  use_count   INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active'  -- active | archived
);

-- Связи между заметками (граф). Направленные, с типом.
CREATE TABLE edges (
  src   TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  dst   TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  rel   TEXT NOT NULL,                  -- relates | causes | supersedes | example_of
  PRIMARY KEY (src, dst, rel)
);

-- Полнотекстовый поиск (lexical RAG) — синхронизируется триггерами с notes
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title, body, tags,
  content='notes', content_rowid='rowid'
);
```

Позже (опционально) — semantic-поиск: таблица `notes_vec` через `sqlite-vec` +
**локальный** эмбеддер (у Anthropic нет embeddings-эндпоинта; Voyage — избыточно/приватность).
Фундамент — FTS5; вектора это апгрейд «по смыслу», добавляем когда lexical окажется мало.

### Виды заметок (`kind`)

| kind | что это | пример |
|---|---|---|
| `fact` | факт о проекте/коде | «в auth-сервисе токен валидируется в 3 местах» |
| `rule` | правило поведения агента | «коммиты только `[CLS-XXX]`, без JavaDoc» |
| `playbook` | переиспользуемая процедура | «как выкатить релиз: шаги 1-5» |
| `session` | итог рабочей сессии | «2026-06-14: отревьюил PR auth, нашёл null-баг» |
| `var` | переменная/значение | `JIRA_BOARD_WASABI = 2` |

## Как агент работает с памятью — 3 инструмента (MCP)

Агент не лазает по файлам. Ему дают MCP-сервер `memory` с тремя инструментами.
Регистрируется через существующий `MCPRegistry`.

### `memory_search(query, limit=5)`
Достаёт **только релевантные** заметки (FTS5, ранжирование по релевантности +
свежести + use_count). Возвращает top-K, а не весь дамп. Бампит `last_used_at`/`use_count`.

```jsonc
// вызов
{ "query": "auth сервис ревью токен", "limit": 5 }
// ответ
[
  { "id": "n_a1", "kind": "fact",  "title": "Дублирование валидации токена",
    "body": "В auth-сервисе токен валидируется в 3 местах...", "tags": ["auth"] },
  { "id": "n_b2", "kind": "rule",  "title": "Формат коммитов", "body": "[CLS-XXX]..." },
  { "id": "n_c3", "kind": "session","title": "2026-06-13 ревью auth", "body": "..." }
]
```

### `memory_write(kind, title, body, tags?, links?)`
Создаёт/обновляет заметку. Это **tool-call**, а не «не забудь дописать файл».
Если есть похожая (по title/tags) — обновляет её, а не плодит дубль.

```jsonc
{ "kind": "fact", "title": "Дублирование валидации токена",
  "body": "Вынести в один метод TokenValidator",
  "tags": ["auth","refactor"], "links": ["n_b2"] }
```

### `memory_link(src, dst, rel)`
Связывает две заметки (строит граф).

```jsonc
{ "src": "n_a1", "dst": "n_c3", "rel": "relates" }
```

## Протокол агента (что инжектится в `<agent>.md`)

Короткий блок, заменяет нынешний «Memory protocol v2». Без «читай compiled.md / пиши log.md».

```markdown
## Память
У тебя есть инструменты `memory_search`, `memory_write`, `memory_link`.

### В начале задачи
- Вызови `memory_search("<суть запроса>")` — получишь топ релевантных заметок
  (факты, правила, итоги прошлых сессий). НЕ грузи всю память.

### В конце задачи
- Новый факт/правило/процедуру → `memory_write(...)`.
- Итог сессии → `memory_write(kind="session", ...)` с 2-4 строками сути.
- Связал что-то с прошлым → `memory_link(...)`.
```

## Как агент «помнит прошлую сессию»

1. В конце каждой сессии агент пишет `kind="session"` заметку с итогом.
2. В начале новой сессии `memory_search` по теме запроса достаёт в т.ч. эти session-заметки.
3. → «помнит» прошлое, потому что достал релевантный итог, а не потому что прочитал весь журнал.

Никакого бесконечного `log.md`: старые session-заметки с низким `use_count` и старым
`last_used_at` можно архивировать (`status='archived'`) фоном — decay вместо свалки.

## UI в CAM (для человека)

Вкладка «Память» в `AgentDetailView` (заменяет `AgentMemoryV2Card`):

- **Список заметок** с поиском (тот же FTS5) и фильтром по `kind`.
- **Граф связей** — узлы = заметки, рёбра = `edges`. Клик по узлу → инспектор заметки;
  видно бэклинки («что ссылается на это»). Рисуем нативно поверх GRDB (force-directed).
- **Инспектор/редактор** — правка `title`/`body`/`tags`, удаление, ручное связывание.
- Живое обновление через `ValueObservation` (агент записал → граф обновился).

Это убирает «лазать по куче файлов». Obsidian не нужен: граф и поиск — прямо в CAM,
а агенту даём `memory_search` (умный retrieval), которого у Obsidian-связки в принципе нет.

(Опц. бонус позже: экспорт заметок в Obsidian-совместимые `.md` + `[[links]]`, если
захочется открыть vault в Obsidian. Не основа — «на всякий».)

## Миграция с v2

Одноразовый шаг при первом запуске v3:
- `context.md` → заметки `kind=fact`;
- `rules.yaml` → `kind=rule`;
- `playbooks.md` → `kind=playbook`;
- `vars.json` → `kind=var`;
- `log.md` → разбить по сессиям на `kind=session`.

Старые файлы не удаляем сразу — переименовываем в `_v2_backup/`.

## Этапы реализации

1. **БД-слой**: GRDB в `Package.swift`, `MemoryStore` (схема + миграции + CRUD + FTS5).
2. **MCP-сервер** `memory` (search/write/link) + регистрация в `MCPRegistry`, инжект протокола.
3. **UI**: список + поиск (быстро), затем граф-вью.
4. **Миграция** v2 → v3 + кнопка в UI.
5. **(Опц.)** semantic-поиск: `sqlite-vec` + локальный эмбеддер.
6. **(Опц.)** экспорт в Obsidian-совместимый markdown.

Удаляем после стабилизации: `MemoryCompilerService.swift`, `tools/compile-memory.py`,
`compiled.md`/`log.md`-логику (двойной компилятор и дамп уходят).
```
