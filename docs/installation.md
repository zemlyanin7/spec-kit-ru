# Руководство по установке

## Предварительные требования

- **Linux/macOS** (или Windows; скрипты PowerShell теперь поддерживаются без WSL)
- Агент для работы с кодом: [Claude Code](https://www.anthropic.com/claude-code), [GitHub Copilot](https://code.visualstudio.com/) или [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [uv](https://docs.astral.sh/uv/) для управления пакетами
- [Python 3.11+](https://www.python.org/downloads/)
- [Git](https://git-scm.com/downloads)

## Установка

### Инициализация нового проекта

Самый простой способ начать — инициализировать новый проект:

```bash
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <PROJECT_NAME>
```

Либо инициализировать проект в текущей директории:

```bash
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init .
# или используйте флаг --here
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init --here
```

### Указание AI-агента

Вы можете заранее выбрать AI-агента при инициализации:

```bash
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --ai claude
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --ai gemini
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --ai copilot
```

### Выбор типа скриптов (Shell или PowerShell)

Все автоматизированные скрипты теперь имеют варианты и на Bash (`.sh`), и на PowerShell (`.ps1`).

Автоматическое поведение:
- Windows по умолчанию: `ps`
- На других ОС по умолчанию: `sh`
- В интерактивном режиме появится запрос, если не передан `--script`

Принудительный выбор конкретного типа скриптов:
```bash
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --script sh
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --script ps
```

### Пропуск проверки инструментов агента

Если хотите получить шаблоны, не проверяя наличие необходимых инструментов:

```bash
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify init <project_name> --ai claude --ignore-agent-tools
```

## Проверка

После инициализации вы должны увидеть следующие команды в своём AI-агенте:
- `/speckit.specify` — создание спецификаций
- `/speckit.plan` — генерация планов реализации  
- `/speckit.tasks` — декомпозиция на конкретные задачи

Каталог `.specify/scripts` будет содержать как `.sh`, так и `.ps1` скрипты.

## Устранение неполадок

### Git Credential Manager на Linux

Если у вас возникают проблемы с аутентификацией Git на Linux, вы можете установить Git Credential Manager:

```bash
#!/usr/bin/env bash
set -e
echo "Скачивание Git Credential Manager v2.6.1..."
wget https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.6.1/gcm-linux_amd64.2.6.1.deb
echo "Установка Git Credential Manager..."
sudo dpkg -i gcm-linux_amd64.2.6.1.deb
echo "Настройка Git для использования GCM..."
git config --global credential.helper manager
echo "Очистка временных файлов..."
rm gcm-linux_amd64.2.6.1.deb
```
