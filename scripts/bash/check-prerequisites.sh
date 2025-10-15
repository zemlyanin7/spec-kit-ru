#!/usr/bin/env bash

# Унифицированная проверка предпосылок
#
# Скрипт выполняет комплексную проверку условий для процесса Spec-Driven Development.
# Он объединяет функции, ранее распределённые по нескольким отдельным скриптам.
#
# Использование: ./check-prerequisites.sh [ПАРАМЕТРЫ]
#
# ПАРАМЕТРЫ:
#   --json              вывод в формате JSON
#   --require-tasks     требовать наличие tasks.md (для этапа реализации)
#   --include-tasks     включать tasks.md в список AVAILABLE_DOCS
#   --paths-only        выводить только пути без проверки
#   --help, -h          показать справку
#
# ВЫВОД:
#   JSON: {"FEATURE_DIR":"...", "AVAILABLE_DOCS":["..."]}
#   Текст: FEATURE_DIR:... \n AVAILABLE_DOCS: \n ✓/✗ file.md
#   Только пути: REPO_ROOT: ... \n BRANCH: ... \n FEATURE_DIR: ... и т.д.

set -e

# Разбор аргументов командной строки
JSON_MODE=false
REQUIRE_TASKS=false
INCLUDE_TASKS=false
PATHS_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --require-tasks)
            REQUIRE_TASKS=true
            ;;
        --include-tasks)
            INCLUDE_TASKS=true
            ;;
        --paths-only)
            PATHS_ONLY=true
            ;;
        --help|-h)
            cat << 'EOF'
Использование: check-prerequisites.sh [ПАРАМЕТРЫ]

Единая проверка предпосылок для процесса Spec-Driven Development.

ПАРАМЕТРЫ:
  --json              вывод в формате JSON
  --require-tasks     требовать наличие tasks.md (этап реализации)
  --include-tasks     включить tasks.md в список AVAILABLE_DOCS
  --paths-only        выводить только пути (без проверки предпосылок)
  --help, -h          показать эту справку

ПРИМЕРЫ:
  # Проверка предпосылок для задач (требуется plan.md)
  ./check-prerequisites.sh --json
  
  # Проверка предпосылок реализации (нужны plan.md и tasks.md)
  ./check-prerequisites.sh --json --require-tasks --include-tasks
  
  # Получить только пути фичи (без проверки)
  ./check-prerequisites.sh --paths-only
  
EOF
            exit 0
            ;;
        *)
            echo "ERROR: Неизвестный параметр '$arg'. Используйте --help для справки." >&2
            exit 1
            ;;
    esac
done

# Подключаем общие функции
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Получаем пути фичи и валидируем ветку
eval $(get_feature_paths)
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

# В режиме paths-only выводим пути и завершаем работу (совместим с JSON)
if $PATHS_ONLY; then
    if $JSON_MODE; then
        # Минимальный JSON с путями (без проверки)
        printf '{"REPO_ROOT":"%s","BRANCH":"%s","FEATURE_DIR":"%s","FEATURE_SPEC":"%s","IMPL_PLAN":"%s","TASKS":"%s"}\n' \
            "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "$FEATURE_SPEC" "$IMPL_PLAN" "$TASKS"
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "BRANCH: $CURRENT_BRANCH"
        echo "FEATURE_DIR: $FEATURE_DIR"
        echo "FEATURE_SPEC: $FEATURE_SPEC"
        echo "IMPL_PLAN: $IMPL_PLAN"
        echo "TASKS: $TASKS"
    fi
    exit 0
fi

# Проверяем обязательные каталоги и файлы
if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Каталог фичи не найден: $FEATURE_DIR" >&2
    echo "Сначала выполните /specify-ru.specify, чтобы создать структуру фичи." >&2
    exit 1
fi

if [[ ! -f "$IMPL_PLAN" ]]; then
    echo "ERROR: plan.md не найден в $FEATURE_DIR" >&2
    echo "Сначала выполните /specify-ru.plan, чтобы создать план реализации." >&2
    exit 1
fi

# Проверяем наличие tasks.md при необходимости
if $REQUIRE_TASKS && [[ ! -f "$TASKS" ]]; then
    echo "ERROR: tasks.md не найден в $FEATURE_DIR" >&2
    echo "Сначала выполните /specify-ru.tasks, чтобы создать список задач." >&2
    exit 1
fi

# Формируем список доступных документов
docs=()

# Всегда проверяем эти необязательные документы
[[ -f "$RESEARCH" ]] && docs+=("research.md")
[[ -f "$DATA_MODEL" ]] && docs+=("data-model.md")

# Каталог contracts проверяем, только если он существует и не пустой
if [[ -d "$CONTRACTS_DIR" ]] && [[ -n "$(ls -A "$CONTRACTS_DIR" 2>/dev/null)" ]]; then
    docs+=("contracts/")
fi

[[ -f "$QUICKSTART" ]] && docs+=("quickstart.md")

# Добавляем tasks.md, если это запрошено и файл существует
if $INCLUDE_TASKS && [[ -f "$TASKS" ]]; then
    docs+=("tasks.md")
fi

# Формируем вывод
if $JSON_MODE; then
    # Собираем JSON-массив документов
    if [[ ${#docs[@]} -eq 0 ]]; then
        json_docs="[]"
    else
        json_docs=$(printf '"%s",' "${docs[@]}")
        json_docs="[${json_docs%,}]"
    fi
    
    printf '{"FEATURE_DIR":"%s","AVAILABLE_DOCS":%s}\n' "$FEATURE_DIR" "$json_docs"
else
    # Текстовый вывод
    echo "FEATURE_DIR:$FEATURE_DIR"
    echo "AVAILABLE_DOCS:"
    
    # Показываем статус каждого потенциального документа
    check_file "$RESEARCH" "research.md"
    check_file "$DATA_MODEL" "data-model.md"
    check_dir "$CONTRACTS_DIR" "contracts/"
    check_file "$QUICKSTART" "quickstart.md"
    
    if $INCLUDE_TASKS; then
        check_file "$TASKS" "tasks.md"
    fi
fi
