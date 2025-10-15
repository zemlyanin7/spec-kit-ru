# Руководство по локальной разработке

Это руководство показывает, как итеративно работать с CLI `specify` локально, не публикуя релиз и не коммитя изменения в `main`.

> Скрипты теперь доступны и в Bash (`.sh`), и в PowerShell (`.ps1`) вариантах. CLI автоматически выбирает вариант в зависимости от ОС, если не передан флаг `--script sh|ps`.

## 1. Клонирование и переключение веток

```bash
git clone https://github.com/zemlyanin7/spec-kit-ru.git
cd spec-kit-ru
# Работаем в собственной фиче-ветке
git checkout -b your-feature-branch
```

## 2. Запуск CLI напрямую (самая быстрая обратная связь)

Можно выполнять CLI через модульный entrypoint без установки:

```bash
# Из корня репозитория
python -m src.specify_cli --help
python -m src.specify_cli init demo-project --ai claude --ignore-agent-tools --script sh
```

Если предпочитаете запуск скрипта как файла (через shebang):

```bash
python src/specify_cli/__init__.py init demo-project --script ps
```

## 3. Установка в режиме editable (изолированная среда)

Создайте изолированную среду через `uv`, чтобы зависимости разрешались так же, как у конечных пользователей:

```bash
# Создание и активация виртуальной среды (uv управляет .venv автоматически)
uv venv
source .venv/bin/activate  # или в PowerShell на Windows: .venv\Scripts\Activate.ps1

# Установка проекта в режиме editable
uv pip install -e .

# Теперь доступна точка входа 'specify'
specify --help
```

Повторный запуск после изменений кода не требует переустановки благодаря режиму editable.

## 4. Запуск через uvx напрямую из Git (текущая ветка)

`uvx` может выполняться из локального пути (или Git-ссылки), чтобы моделировать сценарии пользователей:

```bash
uvx --from . specify init demo-uvx --ai copilot --ignore-agent-tools --script sh
```

Можно указать uvx на конкретную ветку без слияния:

```bash
# Сначала запушьте рабочую ветку
git push origin your-feature-branch
uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git@your-feature-branch specify init demo-branch-test --script ps
```

### 4a. Абсолютный путь для uvx (запуск из любого места)

Если вы в другой директории, используйте абсолютный путь вместо `.`:

```bash
uvx --from /mnt/c/GitHub/spec-kit-ru specify --help
uvx --from /mnt/c/GitHub/spec-kit-ru specify init demo-anywhere --ai copilot --ignore-agent-tools --script sh
```

Для удобства определите переменную окружения:
```bash
export SPEC_KIT_SRC=/mnt/c/GitHub/spec-kit-ru
uvx --from "$SPEC_KIT_SRC" specify init demo-env --ai copilot --ignore-agent-tools --script ps
```

(Необязательно) Определите shell-функцию:
```bash
specify-dev() { uvx --from /mnt/c/GitHub/spec-kit-ru specify "$@"; }
# Затем
specify-dev --help
```

## 5. Проверка прав на скрипты

После выполнения `init` убедитесь, что shell-скрипты исполняемые в POSIX-системах:

```bash
ls -l scripts | grep .sh
# Ожидается бит исполнения для владельца (например, -rwxr-xr-x)
```
На Windows вместо этого используйте `.ps1` скрипты (chmod не нужен).

## 6. Запуск линтера / базовых проверок (добавьте свои)

Пока нет обязательной конфигурации линтера, но можно быстро проверить возможность импорта:
```bash
python -c "import specify_cli; print('Import OK')"
```

## 7. Локальная сборка wheel (по желанию)

Проверьте пакетирование перед публикацией:

```bash
uv build
ls dist/
```
При необходимости установите собранный артефакт во временную чистую среду.

## 8. Использование временного рабочего каталога

При тестировании `init --here` в «грязной» директории создайте временное пространство:

```bash
mkdir /tmp/spec-test && cd /tmp/spec-test
python -m src.specify_cli init --here --ai claude --ignore-agent-tools --script sh  # если репозиторий скопирован сюда
```
Или скопируйте только изменённую часть CLI, если нужен более лёгкий стенд.

## 9. Отладка при пропуске сетевых/TLS проверок

Если во время экспериментов нужно обойти проверку TLS:

```bash
specify check --skip-tls
specify init demo --skip-tls --ai gemini --ignore-agent-tools --script ps
```
(Используйте только для локальных экспериментов.)

## 10. Краткое резюме цикла быстрых правок

| Действие | Команда |
|----------|---------|
| Запуск CLI напрямую | `python -m src.specify_cli --help` |
| Установка в editable | `uv pip install -e .`, затем `specify ...` |
| Локальный uvx (корень репо) | `uvx --from . specify ...` |
| Локальный uvx (абсолютный путь) | `uvx --from /mnt/c/GitHub/spec-kit-ru specify ...` |
| uvx с Git-ветки | `uvx --from git+URL@branch specify ...` |
| Сборка wheel | `uv build` |

## 11. Очистка

Быстро удалите артефакты сборки и виртуальную среду:
```bash
rm -rf .venv dist build *.egg-info
```

## 12. Частые проблемы

| Симптом | Решение |
|---------|---------|
| `ModuleNotFoundError: typer` | Выполните `uv pip install -e .` |
| Скрипты не исполняются (Linux) | Повторите init или `chmod +x scripts/*.sh` |
| Шаг с Git пропущен | Был передан `--no-git` или Git не установлен |
| Загружен неправильный тип скриптов | Явно укажите `--script sh` или `--script ps` |
| Ошибки TLS в корпоративной сети | Попробуйте `--skip-tls` (не для продакшена) |

## 13. Следующие шаги

- Обновите документацию и пройдите Quick Start, используя модифицированный CLI
- Откройте PR, когда будете довольны результатом
- (Необязательно) Пометьте релиз после попадания изменений в `main`
