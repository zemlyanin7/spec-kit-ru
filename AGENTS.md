# AGENTS.md

## О Spec Kit и Specify

**GitHub Spec Kit** — это комплексный набор инструментов для внедрения подхода разработки, управляемой спецификациями (Spec-Driven Development, SDD). Набор включает шаблоны, скрипты и рабочие процессы, которые помогают командам последовательно и структурировано создавать программные продукты.

**Specify CLI** — это интерфейс командной строки, который разворачивает проекты с использованием Spec Kit. Он настраивает структуры каталогов, шаблоны и интеграции с ИИ-агентами, необходимые для работы по методологии Spec-Driven Development.

Набор поддерживает несколько ИИ-помощников, поэтому команды могут работать с привычными инструментами, не нарушая общую структуру проекта и практики разработки.

---

## Общие правила

- Любые изменения в `__init__.py` (Specify CLI) требуют увеличения версии в `pyproject.toml` и добавления записи в `CHANGELOG.md`.

## Добавление поддержки нового агента

В этом разделе описано, как интегрировать нового ИИ-агента (код-ассистента) в Specify CLI. Используйте руководство как подсказку при добавлении в рабочий процесс Spec-Driven Development.

### Общее представление

Specify поддерживает разных ИИ-агентов, создавая для них специфические файлы команд и каталоги во время инициализации проекта. Для каждого агента определены собственные соглашения по:

- **Формату командных файлов** (Markdown, TOML и т.п.)
- **Структурам каталогов** (`.claude/commands/`, `.windsurf/workflows/` и др.)
- **Способам вызова команд** (slash-команды, CLI-инструменты и т.п.)
- **Форматам передачи аргументов** (`$ARGUMENTS`, `{{args}}` и т.д.)

### Поддерживаемые агенты

| Агент | Каталог | Формат | CLI | Описание |
|-------|---------|--------|-----|----------|
| **Claude Code** | `.claude/commands/` | Markdown | `claude` | CLI от Anthropic |
| **Gemini CLI** | `.gemini/commands/` | TOML | `gemini` | Gemini CLI от Google |
| **GitHub Copilot** | `.github/prompts/` | Markdown | CLI не требуется (IDE) | GitHub Copilot во VS Code |
| **Cursor** | `.cursor/commands/` | Markdown | `cursor-agent` | Cursor CLI |
| **Qwen Code** | `.qwen/commands/` | TOML | `qwen` | CLI от Alibaba |
| **opencode** | `.opencode/command/` | Markdown | `opencode` | opencode CLI |
| **Codex CLI** | `.codex/commands/` | Markdown | `codex` | Codex CLI |
| **Windsurf** | `.windsurf/workflows/` | Markdown | CLI не требуется (IDE) | Рабочие процессы Windsurf |
| **Kilo Code** | `.kilocode/rules/` | Markdown | CLI не требуется (IDE) | IDE Kilo Code |
| **Auggie CLI** | `.augment/rules/` | Markdown | `auggie` | Auggie CLI |
| **Roo Code** | `.roo/rules/` | Markdown | CLI не требуется (IDE) | Roo Code IDE |
| **CodeBuddy** | `.codebuddy/commands/` | Markdown | `codebuddy` | CodeBuddy |
| **Amazon Q Developer CLI** | `.amazonq/prompts/` | Markdown | `q` | Amazon Q Developer CLI |

### Пошаговая интеграция

Ниже пример для гипотетического нового агента.

#### 1. Добавить в AGENT_CONFIG

**Важно:** в качестве ключа используйте реальное имя исполняемого файла CLI, без сокращений.

Добавьте нового агента в словарь `AGENT_CONFIG` в `src/specify_cli/__init__.py`. Это **единственный источник правды** с метаданными по агентам:

```python
AGENT_CONFIG = {
    # ... остальные агенты ...
    "new-agent-cli": {  # ключ — реальное название CLI-инструмента
        "name": "New Agent Display Name",
        "folder": ".newagent/",  # каталог с файлами агента
        "install_url": "https://example.com/install",  # URL с инструкцией по установке (или None для IDE-агентов)
        "requires_cli": True,  # True — если нужен CLI, False — если агент IDE-ориентированный
    },
}
```

**Ключевое правило:** значение ключа должно совпадать с именем исполняемого файла. Например:

- ✅ `"cursor-agent"` — соответствует реальному бинарнику
- ❌ `"cursor"` — сокращение, не совпадает с CLI-инструментом

Так не понадобится добавлять частные исключения по всему коду.

**Описание полей:**
- `name`: человекочитаемое имя агента
- `folder`: каталог с файлами агента относительно корня проекта
- `install_url`: ссылка на документацию по установке (или `None` для IDE)
- `requires_cli`: флаг, указывающий, нужно ли проверять наличие CLI во время инициализации

#### 2. Обновить подсказки в CLI

Дополните текст подсказки параметра `--ai` в команде `init()`:

```python
ai_assistant: str = typer.Option(
    None,
    "--ai",
    help="AI assistant to use: claude, gemini, copilot, cursor-agent, qwen, opencode, codex, windsurf, kilocode, auggie, codebuddy, new-agent-cli, or q",
)
```

Также обновите докстринги, примеры и сообщения об ошибках, в которых перечисляются доступные агенты.

#### 3. Обновить документацию (README)

В разделе **Supported AI Agents** (`README.md`) добавьте сведения о новом агенте:

- впишите его в таблицу с уровнем поддержки;
- дайте ссылку на официальный сайт;
- добавьте замечания, если ими стоит поделиться;
- убедитесь, что таблица отформатирована корректно.

#### 4. Обновить скрипт сборки релизов

В файле `.github/workflows/scripts/create-release-packages.sh`:

- добавьте имя агента в массив `ALL_AGENTS`:
  ```bash
  ALL_AGENTS=(claude gemini copilot cursor-agent qwen opencode windsurf q)
  ```
- добавьте обработку в `case` с подготовкой структуры каталогов:
  ```bash
  case $agent in
    # ... существующие ветки ...
    windsurf)
      mkdir -p "$base_dir/.windsurf/workflows"
      generate_commands windsurf md "\$ARGUMENTS" "$base_dir/.windsurf/workflows" "$script" ;;
  esac
  ```

#### 4. Обновить скрипт релиза GitHub

В `.github/workflows/scripts/create-github-release.sh` включите архивы нового агента:

```bash
gh release create "$VERSION" \
  # ... текущие пакеты ...
  .genreleases/spec-kit-template-windsurf-sh-"$VERSION".zip \
  .genreleases/spec-kit-template-windsurf-ps-"$VERSION".zip \
  # Добавьте архивы нового агента здесь
```

#### 5. Обновить скрипты контекста агентов

**Bash (`scripts/bash/update-agent-context.sh`):**

- добавьте переменную с файловым путём:
  ```bash
  WINDSURF_FILE="$REPO_ROOT/.windsurf/rules/specify-rules.md"
  ```
- расширьте `case`:
  ```bash
  case "$AGENT_TYPE" in
    # ... существующие ветки ...
    windsurf) update_agent_file "$WINDSURF_FILE" "Windsurf" ;;
    "")
      # ... остальные проверки ...
      [ -f "$WINDSURF_FILE" ] && update_agent_file "$WINDSURF_FILE" "Windsurf";
      # Обновите условие создания по умолчанию
      ;;
  esac
  ```

**PowerShell (`scripts/powershell/update-agent-context.ps1`):**

- добавьте переменную:
  ```powershell
  $windsurfFile = Join-Path $repoRoot '.windsurf/rules/specify-rules.md'
  ```
- расширьте `switch`:
  ```powershell
  switch ($AgentType) {
      # ... существующие ветки ...
      'windsurf' { Update-AgentFile $windsurfFile 'Windsurf' }
      '' {
          foreach ($pair in @(
              # ... текущие пары ...
              @{file=$windsurfFile; name='Windsurf'}
          )) {
              if (Test-Path $pair.file) { Update-AgentFile $pair.file $pair.name }
          }
          # Обновите условие создания по умолчанию
      }
  }
  ```

#### 6. Проверки CLI (опционально)

Если агент требует CLI-инструмент, добавьте проверки в команды `check()` и `init()`:

```python
# В команде check()
tracker.add("windsurf", "Windsurf IDE (optional)")
windsurf_ok = check_tool_for_tracker("windsurf", "https://windsurf.com/", tracker)

# Валидация init (если CLI обязателен)
elif selected_ai == "windsurf":
    if not check_tool("windsurf", "Install from: https://windsurf.com/"):
        console.print("[red]Error:[/red] Windsurf CLI is required for Windsurf projects")
        agent_tool_missing = True
```

> **Примечание.** Сейчас проверки CLI выполняются автоматически на основании поля `requires_cli` в `AGENT_CONFIG`. Дополнительный код не требуется: `check()` и `init()` сами обходят `AGENT_CONFIG` и проверяют нужные инструменты.

## Важные решения по дизайну

### Настоящие имена CLI как ключи

**Критично:** при добавлении агента в `AGENT_CONFIG` используйте **реальное имя исполняемого файла**, а не удобное сокращение.

**Почему это важно:**
- `check_tool()` использует `shutil.which(tool)` для поиска исполняемого файла;
- если ключ не совпадает с CLI-файлом, придётся добавлять исключения по всему коду;
- это усложняет поддержку и увеличивает риск ошибок.

**Пример с Cursor:**

❌ Неверно (нужны доп. сопоставления):
```python
AGENT_CONFIG = {
    "cursor": {
        "name": "Cursor",
        # ...
    }
}

cli_tool = agent_key
if agent_key == "cursor":
    cli_tool = "cursor-agent"
```

✅ Верно (без дополнительных преобразований):
```python
AGENT_CONFIG = {
    "cursor-agent": {
        "name": "Cursor",
        # ...
    }
}
```

**Преимущества:**
- не нужны специальные правила по всему проекту;
- код понятнее и легче обслуживать;
- риск ошибок при добавлении новых агентов снижается;
- проверки инструментов работают «из коробки».

## Категории агентов

### CLI-агенты
Требуют установленного CLI-инструмента:

- **Claude Code**: `claude`
- **Gemini CLI**: `gemini`
- **Cursor**: `cursor-agent`
- **Qwen Code**: `qwen`
- **opencode**: `opencode`
- **CodeBuddy**: `codebuddy`

### IDE-агенты
Работают непосредственно в IDE:

- **GitHub Copilot**: интегрируется в VS Code и совместимые редакторы
- **Windsurf**: встроен в IDE Windsurf

## Форматы командных файлов

### Markdown
Используется агентами Claude, Cursor, opencode, Windsurf, Amazon Q Developer:

```markdown
---
description: "Описание команды"
---

Текст команды с плейсхолдерами {SCRIPT} и $ARGUMENTS.
```

### TOML
Используется агентами Gemini и Qwen:

```toml
description = "Описание команды"

prompt = """
Текст команды с плейсхолдерами {SCRIPT} и {{args}}.
"""
```

## Правила для каталогов

- **CLI-агенты**: как правило, используют структуру `.<имя-агента>/commands/`
- **IDE-агенты**: следует учитывать соглашения IDE:
  - Copilot: `.github/prompts/`
  - Cursor: `.cursor/commands/`
  - Windsurf: `.windsurf/workflows/`

## Паттерны аргументов

Разные агенты ожидают собственные плейсхолдеры:

- **Markdown/Prompt**: `$ARGUMENTS`
- **TOML**: `{{args}}`
- **Путь к скрипту**: `{SCRIPT}`
- **Имя агента**: `__AGENT__`

## Тестирование интеграции нового агента

1. **Проверка сборки**: локально запустите скрипт формирования пакета.
2. **CLI-тест**: выполните `specify init --ai <agent>`.
3. **Проверка файлов**: убедитесь в корректной структуре каталога и созданных файлах.
4. **Валидация команд**: убедитесь, что сгенерированные команды работают с агентом.
5. **Контекст**: протестируйте обновление контекста с помощью соответствующих скриптов.

## Распространённые ошибки

1. **Сокращённые ключи вместо настоящих CLI** — всегда используйте реальные имена (`"cursor-agent"`, а не `"cursor"`).
2. **Забытые обновления скриптов** — правьте версии и для bash-, и для PowerShell-скриптов.
3. **Неверный `requires_cli`** — `True` только если действительно нужен CLI; `False` — для IDE-агентов.
4. **Неверные плейсхолдеры** — соблюдайте формат под конкретного агента (`$ARGUMENTS` в Markdown, `{{args}}` в TOML).
5. **Ошибки в названии каталогов** — строго следуйте соглашениям конкретного агента.
6. **Непоследовательные подсказки** — обновляйте все пользовательские тексты (справка, докстринги, README, ошибки).

## Что учитывать в будущем

При добавлении нового агента:

- учитывайте нативные команды и рабочие процессы агента;
- проверяйте совместимость с подходом SDD;
- документируйте особые требования или ограничения;
- обновляйте это руководство с накопленным опытом;
- убедитесь, что ключ в `AGENT_CONFIG` совпадает с реальным CLI.

---

*Обновляйте этот документ при добавлении новых агентов, чтобы поддерживать актуальность и полноту информации.*
