#!/usr/bin/env bash

set -e

# Разбор аргументов командной строки
JSON_MODE=false
ARGS=()

for arg in "$@"; do
    case "$arg" in
        --json) 
            JSON_MODE=true 
            ;;
        --help|-h) 
            echo "Использование: $0 [--json]"
            echo "  --json    вывод в формате JSON"
            echo "  --help    показать эту справку"
            exit 0 
            ;;
        *) 
            ARGS+=("$arg") 
            ;;
    esac
done

# Определяем каталог скрипта и подключаем общие функции
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Получаем пути и переменные из общего модуля
eval $(get_feature_paths)

# Проверяем, находимся ли на корректной фиче-ветке (только для git-репозиториев)
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

# Гарантируем наличие каталога фичи
mkdir -p "$FEATURE_DIR"

# Копируем шаблон плана, если он доступен
TEMPLATE="$REPO_ROOT/.specify/templates/plan-template.md"
if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$IMPL_PLAN"
    echo "Скопирован шаблон плана в $IMPL_PLAN"
else
    echo "WARNING: Шаблон плана не найден по пути $TEMPLATE"
    # Создаём базовый файл плана, если шаблон отсутствует
    touch "$IMPL_PLAN"
fi

# Формируем вывод
if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","IMPL_PLAN":"%s","SPECS_DIR":"%s","BRANCH":"%s","HAS_GIT":"%s"}\n' \
        "$FEATURE_SPEC" "$IMPL_PLAN" "$FEATURE_DIR" "$CURRENT_BRANCH" "$HAS_GIT"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "IMPL_PLAN: $IMPL_PLAN" 
    echo "SPECS_DIR: $FEATURE_DIR"
    echo "BRANCH: $CURRENT_BRANCH"
    echo "HAS_GIT: $HAS_GIT"
fi
