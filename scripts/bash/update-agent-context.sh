#!/usr/bin/env bash

# Обновляет контекстные файлы агентов на основе plan.md
#
# Скрипт поддерживает актуальность контекстов ИИ-агентов, разбирая спецификации фич
# и обновляя конфигурационные файлы агентов информацией о проекте.
#
# ОСНОВНЫЕ ФУНКЦИИ:
# 1. Проверка окружения
#    - Валидирует структуру git-репозитория и текущую ветку
#    - Проверяет наличие планов plan.md и шаблонов
#    - Убеждается в доступности файлов и корректных правах
#
# 2. Извлечение данных плана
#    - Разбирает plan.md, чтобы получить метаданные проекта
#    - Определяет язык/версию, фреймворки, базы данных и тип проекта
#    - Корректно обрабатывает отсутствующие или неполные данные
#
# 3. Управление файлами агентов
#    - Создаёт новые контексты из шаблонов при необходимости
#    - Обновляет существующие файлы свежей информацией о проекте
#    - Сохраняет ручные правки и пользовательские настройки
#    - Поддерживает разные форматы и структуры каталогов агентов
#
# 4. Генерация содержимого
#    - Формирует команду сборки/тестов для выбранного языка
#    - Создаёт подходящую структуру каталогов проекта
#    - Обновляет стек технологий и раздел последних изменений
#    - Поддерживает единое форматирование и метки времени
#
# 5. Многоплатформенная поддержка
#    - Учитывает пути и соглашения каждого агента
#    - Поддерживает: Claude, Gemini, Copilot, Cursor, Qwen, opencode, Codex, Windsurf, Kilo Code, Auggie CLI, Amazon Q Developer CLI
#    - Работа возможна для конкретного агента или для всех найденных файлов
#    - Создаёт файл Claude по умолчанию, если не найден ни один агент
#
# Использование: ./update-agent-context.sh [тип_агента]
# Типы агентов: claude|gemini|copilot|cursor-agent|qwen|opencode|codex|windsurf|kilocode|auggie|q
# Если параметр не указан — обновляются все найденные файлы агентов

set -e

# Включаем строгую обработку ошибок
set -u
set -o pipefail

#==============================================================================
# Конфигурация и глобальные переменные
#==============================================================================

# Определяем каталог скрипта и подключаем общие функции
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Получаем пути и переменные из общего модуля
eval $(get_feature_paths)

NEW_PLAN="$IMPL_PLAN"  # Псевдоним для совместимости с существующим кодом
AGENT_TYPE="${1:-}"

# Пути к файлам конкретных агентов
CLAUDE_FILE="$REPO_ROOT/CLAUDE.md"
GEMINI_FILE="$REPO_ROOT/GEMINI.md"
COPILOT_FILE="$REPO_ROOT/.github/copilot-instructions.md"
CURSOR_FILE="$REPO_ROOT/.cursor/rules/specify-rules.mdc"
QWEN_FILE="$REPO_ROOT/QWEN.md"
AGENTS_FILE="$REPO_ROOT/AGENTS.md"
WINDSURF_FILE="$REPO_ROOT/.windsurf/rules/specify-rules.md"
KILOCODE_FILE="$REPO_ROOT/.kilocode/rules/specify-rules.md"
AUGGIE_FILE="$REPO_ROOT/.augment/rules/specify-rules.md"
ROO_FILE="$REPO_ROOT/.roo/rules/specify-rules.md"
CODEBUDDY_FILE="$REPO_ROOT/CODEBUDDY.md"
Q_FILE="$REPO_ROOT/AGENTS.md"

# Файл шаблона
TEMPLATE_FILE="$REPO_ROOT/.specify/templates/agent-file-template.md"

# Глобальные переменные для данных, извлечённых из плана
NEW_LANG=""
NEW_FRAMEWORK=""
NEW_DB=""
NEW_PROJECT_TYPE=""

#==============================================================================
# Вспомогательные функции
#==============================================================================

log_info() {
    echo "INFO: $1"
}

log_success() {
    echo "✓ $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

log_warning() {
    echo "WARNING: $1" >&2
}

# Функция очистки временных файлов
cleanup() {
    local exit_code=$?
    rm -f /tmp/agent_update_*_$$
    rm -f /tmp/manual_additions_$$
    exit $exit_code
}

# Устанавливаем ловушку для очистки
trap cleanup EXIT INT TERM

#==============================================================================
# Функции валидации
#==============================================================================

validate_environment() {
    # Проверяем, определена ли текущая фича (для git и окружений без git)
    if [[ -z "$CURRENT_BRANCH" ]]; then
        log_error "Не удалось определить текущую фичу"
        if [[ "$HAS_GIT" == "true" ]]; then
            log_info "Убедитесь, что вы работаете во фичевой ветке"
        else
            log_info "Установите переменную SPECIFY_FEATURE или заранее создайте фичу"
        fi
        exit 1
    fi
    
    # Проверяем наличие plan.md
    if [[ ! -f "$NEW_PLAN" ]]; then
        log_error "plan.md не найден: $NEW_PLAN"
        log_info "Убедитесь, что работаете с фичей, у которой есть каталог spec"
        if [[ "$HAS_GIT" != "true" ]]; then
            log_info "Используйте: export SPECIFY_FEATURE=имя-фичи или создайте новую фичу"
        fi
        exit 1
    fi
    
    # Проверяем наличие шаблона (требуется для создания новых файлов)
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_warning "Шаблон не найден по пути $TEMPLATE_FILE"
        log_warning "Создание новых файлов агентов завершится ошибкой"
    fi
}

#==============================================================================
# Разбор плана
#==============================================================================

extract_plan_field() {
    local field_pattern="$1"
    local plan_file="$2"
    
    grep "^\*\*${field_pattern}\*\*: " "$plan_file" 2>/dev/null | \
        head -1 | \
        sed "s|^\*\*${field_pattern}\*\*: ||" | \
        sed 's/^[ \t]*//;s/[ \t]*$//' | \
        grep -v "NEEDS CLARIFICATION" | \
        grep -v "^N/A$" || echo ""
}

parse_plan_data() {
    local plan_file="$1"
    
    if [[ ! -f "$plan_file" ]]; then
        log_error "Файл плана не найден: $plan_file"
        return 1
    fi
    
    if [[ ! -r "$plan_file" ]]; then
        log_error "Файл плана недоступен для чтения: $plan_file"
        return 1
    fi
    
    log_info "Разбор данных плана из $plan_file"
    
    NEW_LANG=$(extract_plan_field "Language/Version" "$plan_file")
    NEW_FRAMEWORK=$(extract_plan_field "Primary Dependencies" "$plan_file")
    NEW_DB=$(extract_plan_field "Storage" "$plan_file")
    NEW_PROJECT_TYPE=$(extract_plan_field "Project Type" "$plan_file")
    
    # Фиксируем найденные значения
    if [[ -n "$NEW_LANG" ]]; then
        log_info "Определён язык: $NEW_LANG"
    else
        log_warning "В файле плана отсутствует информация о языке"
    fi
    
    if [[ -n "$NEW_FRAMEWORK" ]]; then
        log_info "Определён фреймворк: $NEW_FRAMEWORK"
    fi
    
    if [[ -n "$NEW_DB" ]] && [[ "$NEW_DB" != "N/A" ]]; then
        log_info "Определена база данных: $NEW_DB"
    fi
    
    if [[ -n "$NEW_PROJECT_TYPE" ]]; then
        log_info "Определён тип проекта: $NEW_PROJECT_TYPE"
    fi
}

format_technology_stack() {
    local lang="$1"
    local framework="$2"
    local parts=()
    
    # Добавляем непустые компоненты
    [[ -n "$lang" && "$lang" != "NEEDS CLARIFICATION" ]] && parts+=("$lang")
    [[ -n "$framework" && "$framework" != "NEEDS CLARIFICATION" && "$framework" != "N/A" ]] && parts+=("$framework")
    
    # Формируем строку с корректным форматированием
    if [[ ${#parts[@]} -eq 0 ]]; then
        echo ""
    elif [[ ${#parts[@]} -eq 1 ]]; then
        echo "${parts[0]}"
    else
        # Соединяем несколько частей через " + "
        local result="${parts[0]}"
        for ((i=1; i<${#parts[@]}; i++)); do
            result="$result + ${parts[i]}"
        done
        echo "$result"
    fi
}

#==============================================================================
# Работа с шаблонами и генерацией содержимого
#==============================================================================

get_project_structure() {
    local project_type="$1"
    
    if [[ "$project_type" == *"web"* ]]; then
        echo "backend/\\nfrontend/\\ntests/"
    else
        echo "src/\\ntests/"
    fi
}

get_commands_for_language() {
    local lang="$1"
    
    case "$lang" in
        *"Python"*)
            echo "cd src && pytest && ruff check ."
            ;;
        *"Rust"*)
            echo "cargo test && cargo clippy"
            ;;
        *"JavaScript"*|*"TypeScript"*)
            echo "npm test && npm run lint"
            ;;
        *)
            echo "# Добавьте команды для $lang"
            ;;
    esac
}

get_language_conventions() {
    local lang="$1"
    echo "$lang: придерживайтесь стандартных соглашений"
}

create_new_agent_file() {
    local target_file="$1"
    local temp_file="$2"
    local project_name="$3"
    local current_date="$4"
    
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "Шаблон не найден: $TEMPLATE_FILE"
        return 1
    fi
    
    if [[ ! -r "$TEMPLATE_FILE" ]]; then
        log_error "Шаблон недоступен для чтения: $TEMPLATE_FILE"
        return 1
    fi
    
    log_info "Создание нового контекстного файла агента по шаблону..."
    
    if ! cp "$TEMPLATE_FILE" "$temp_file"; then
        log_error "Не удалось скопировать файл шаблона"
        return 1
    fi
    
    # Подставляем значения вместо плейсхолдеров
    local project_structure
    project_structure=$(get_project_structure "$NEW_PROJECT_TYPE")
    
    local commands
    commands=$(get_commands_for_language "$NEW_LANG")
    
    local language_conventions
    language_conventions=$(get_language_conventions "$NEW_LANG")
    
    # Выполняем замены с проверкой ошибок
    # Экранируем спецсимволы для sed, используя альтернативный разделитель
    local escaped_lang=$(printf '%s\n' "$NEW_LANG" | sed 's/[\[\.*^$()+{}|]/\\&/g')
    local escaped_framework=$(printf '%s\n' "$NEW_FRAMEWORK" | sed 's/[\[\.*^$()+{}|]/\\&/g')
    local escaped_branch=$(printf '%s\n' "$CURRENT_BRANCH" | sed 's/[\[\.*^$()+{}|]/\\&/g')
    
    # Формируем строки стека технологий и недавних изменений при наличии данных
    local tech_stack
    if [[ -n "$escaped_lang" && -n "$escaped_framework" ]]; then
        tech_stack="- $escaped_lang + $escaped_framework ($escaped_branch)"
    elif [[ -n "$escaped_lang" ]]; then
        tech_stack="- $escaped_lang ($escaped_branch)"
    elif [[ -n "$escaped_framework" ]]; then
        tech_stack="- $escaped_framework ($escaped_branch)"
    else
        tech_stack="- ($escaped_branch)"
    fi

    local recent_change
    if [[ -n "$escaped_lang" && -n "$escaped_framework" ]]; then
        recent_change="- $escaped_branch: Добавлено $escaped_lang + $escaped_framework"
    elif [[ -n "$escaped_lang" ]]; then
        recent_change="- $escaped_branch: Добавлено $escaped_lang"
    elif [[ -n "$escaped_framework" ]]; then
        recent_change="- $escaped_branch: Добавлено $escaped_framework"
    else
        recent_change="- $escaped_branch: Добавлено"
    fi

    local substitutions=(
        "s|\[PROJECT NAME\]|$project_name|"
        "s|\[DATE\]|$current_date|"
        "s|\[EXTRACTED FROM ALL PLAN.MD FILES\]|$tech_stack|"
        "s|\[ACTUAL STRUCTURE FROM PLANS\]|$project_structure|g"
        "s|\[ONLY COMMANDS FOR ACTIVE TECHNOLOGIES\]|$commands|"
        "s|\[LANGUAGE-SPECIFIC, ONLY FOR LANGUAGES IN USE\]|$language_conventions|"
        "s|\[LAST 3 FEATURES AND WHAT THEY ADDED\]|$recent_change|"
    )
    
    for substitution in "${substitutions[@]}"; do
        if ! sed -i.bak -e "$substitution" "$temp_file"; then
            log_error "Не удалось выполнить замену: $substitution"
            rm -f "$temp_file" "$temp_file.bak"
            return 1
        fi
    done
    
    # Преобразуем последовательности \n в реальные переводы строк
    newline=$(printf '\n')
    sed -i.bak2 "s/\\\\n/${newline}/g" "$temp_file"
    
    # Удаляем резервные копии
    rm -f "$temp_file.bak" "$temp_file.bak2"
    
    return 0
}




update_existing_agent_file() {
    local target_file="$1"
    local current_date="$2"
    
    log_info "Обновление существующего контекстного файла агента..."
    
    # Используем один временный файл для атомарного обновления
    local temp_file
    temp_file=$(mktemp) || {
        log_error "Не удалось создать временный файл"
        return 1
    }
    
    # Обрабатываем файл за один проход
    local tech_stack=$(format_technology_stack "$NEW_LANG" "$NEW_FRAMEWORK")
    local new_tech_entries=()
    local new_change_entry=""
    
    # Готовим новые пункты для стека технологий
    if [[ -n "$tech_stack" ]] && ! grep -q "$tech_stack" "$target_file"; then
        new_tech_entries+=("- $tech_stack ($CURRENT_BRANCH)")
    fi
    
    if [[ -n "$NEW_DB" ]] && [[ "$NEW_DB" != "N/A" ]] && [[ "$NEW_DB" != "NEEDS CLARIFICATION" ]] && ! grep -q "$NEW_DB" "$target_file"; then
        new_tech_entries+=("- $NEW_DB ($CURRENT_BRANCH)")
    fi
    
    # Готовим запись о последних изменениях
    if [[ -n "$tech_stack" ]]; then
        new_change_entry="- $CURRENT_BRANCH: Добавлено $tech_stack"
    elif [[ -n "$NEW_DB" ]] && [[ "$NEW_DB" != "N/A" ]] && [[ "$NEW_DB" != "NEEDS CLARIFICATION" ]]; then
        new_change_entry="- $CURRENT_BRANCH: Добавлено $NEW_DB"
    fi
    
    # Построчно обрабатываем файл
    local in_tech_section=false
    local in_changes_section=false
    local tech_entries_added=false
    local changes_entries_added=false
    local existing_changes_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Обработка раздела Active Technologies
        if [[ "$line" == "## Active Technologies" ]]; then
            echo "$line" >> "$temp_file"
            in_tech_section=true
            continue
        elif [[ $in_tech_section == true ]] && [[ "$line" =~ ^##[[:space:]] ]]; then
            # Добавляем новые элементы перед завершением раздела
            if [[ $tech_entries_added == false ]] && [[ ${#new_tech_entries[@]} -gt 0 ]]; then
                printf '%s\n' "${new_tech_entries[@]}" >> "$temp_file"
                tech_entries_added=true
            fi
            echo "$line" >> "$temp_file"
            in_tech_section=false
            continue
        elif [[ $in_tech_section == true ]] && [[ -z "$line" ]]; then
            # Добавляем новые элементы перед пустой строкой раздела
            if [[ $tech_entries_added == false ]] && [[ ${#new_tech_entries[@]} -gt 0 ]]; then
                printf '%s\n' "${new_tech_entries[@]}" >> "$temp_file"
                tech_entries_added=true
            fi
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # Обработка раздела Recent Changes
        if [[ "$line" == "## Recent Changes" ]]; then
            echo "$line" >> "$temp_file"
            # Добавляем запись об изменениях сразу после заголовка
            if [[ -n "$new_change_entry" ]]; then
                echo "$new_change_entry" >> "$temp_file"
            fi
            in_changes_section=true
            changes_entries_added=true
            continue
        elif [[ $in_changes_section == true ]] && [[ "$line" =~ ^##[[:space:]] ]]; then
            echo "$line" >> "$temp_file"
            in_changes_section=false
            continue
        elif [[ $in_changes_section == true ]] && [[ "$line" == "- "* ]]; then
            # Сохраняем только первые два существующих изменения
            if [[ $existing_changes_count -lt 2 ]]; then
                echo "$line" >> "$temp_file"
                ((existing_changes_count++))
            fi
            continue
        fi
        
        # Обновляем отметку времени
        if [[ "$line" =~ \*\*Last\ updated\*\*:.*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]]; then
            echo "$line" | sed "s/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/$current_date/" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$target_file"
    
    # Финальная проверка: если остались в разделе Active Technologies и не добавили новые элементы
    if [[ $in_tech_section == true ]] && [[ $tech_entries_added == false ]] && [[ ${#new_tech_entries[@]} -gt 0 ]]; then
        printf '%s\n' "${new_tech_entries[@]}" >> "$temp_file"
    fi
    
    # Перемещаем временный файл на место целевого атомарно
    if ! mv "$temp_file" "$target_file"; then
        log_error "Не удалось обновить целевой файл"
        rm -f "$temp_file"
        return 1
    fi
    
    return 0
}
#==============================================================================
# Главная функция обновления файлов агента
#==============================================================================

update_agent_file() {
    local target_file="$1"
    local agent_name="$2"
    
    if [[ -z "$target_file" ]] || [[ -z "$agent_name" ]]; then
        log_error "update_agent_file requires target_file and agent_name parameters"
        return 1
    fi
    
    log_info "Обновляется контекст $agent_name: $target_file"
    
    local project_name
    project_name=$(basename "$REPO_ROOT")
    local current_date
    current_date=$(date +%Y-%m-%d)
    
    # Создаём каталог при необходимости
    local target_dir
    target_dir=$(dirname "$target_file")
    if [[ ! -d "$target_dir" ]]; then
        if ! mkdir -p "$target_dir"; then
            log_error "Не удалось создать каталог: $target_dir"
            return 1
        fi
    fi
    
    if [[ ! -f "$target_file" ]]; then
        # Создаём новый файл на основе шаблона
        local temp_file
        temp_file=$(mktemp) || {
            log_error "Не удалось создать временный файл"
            return 1
        }
        
        if create_new_agent_file "$target_file" "$temp_file" "$project_name" "$current_date"; then
            if mv "$temp_file" "$target_file"; then
                log_success "Создан новый контекст $agent_name"
            else
                log_error "Не удалось переместить временный файл в $target_file"
                rm -f "$temp_file"
                return 1
            fi
        else
            log_error "Не удалось создать файл агента"
            rm -f "$temp_file"
            return 1
        fi
    else
        # Обновляем существующий файл
        if [[ ! -r "$target_file" ]]; then
            log_error "Нет доступа на чтение файла: $target_file"
            return 1
        fi
        
        if [[ ! -w "$target_file" ]]; then
            log_error "Нет доступа на запись файла: $target_file"
            return 1
        fi
        
        if update_existing_agent_file "$target_file" "$current_date"; then
            log_success "Обновлён существующий контекст $agent_name"
        else
            log_error "Не удалось обновить файл агента"
            return 1
        fi
    fi
    
    return 0
}

#==============================================================================
# Выбор и обработка агентов
#==============================================================================

update_specific_agent() {
    local agent_type="$1"
    
    case "$agent_type" in
        claude)
            update_agent_file "$CLAUDE_FILE" "Claude Code"
            ;;
        gemini)
            update_agent_file "$GEMINI_FILE" "Gemini CLI"
            ;;
        copilot)
            update_agent_file "$COPILOT_FILE" "GitHub Copilot"
            ;;
        cursor-agent)
            update_agent_file "$CURSOR_FILE" "Cursor IDE"
            ;;
        qwen)
            update_agent_file "$QWEN_FILE" "Qwen Code"
            ;;
        opencode)
            update_agent_file "$AGENTS_FILE" "opencode"
            ;;
        codex)
            update_agent_file "$AGENTS_FILE" "Codex CLI"
            ;;
        windsurf)
            update_agent_file "$WINDSURF_FILE" "Windsurf"
            ;;
        kilocode)
            update_agent_file "$KILOCODE_FILE" "Kilo Code"
            ;;
        auggie)
            update_agent_file "$AUGGIE_FILE" "Auggie CLI"
            ;;
        roo)
            update_agent_file "$ROO_FILE" "Roo Code"
            ;;
        codebuddy)
            update_agent_file "$CODEBUDDY_FILE" "CodeBuddy"
            ;;
        q)
            update_agent_file "$Q_FILE" "Amazon Q Developer CLI"
            ;;
        *)
            log_error "Неизвестный тип агента '$agent_type'"
            log_error "Ожидается: claude|gemini|copilot|cursor-agent|qwen|opencode|codex|windsurf|kilocode|auggie|roo|q"
            exit 1
            ;;
    esac
}

update_all_existing_agents() {
    local found_agent=false
    
    # Проверяем доступные файлы агентов и обновляем, если они существуют
    if [[ -f "$CLAUDE_FILE" ]]; then
        update_agent_file "$CLAUDE_FILE" "Claude Code"
        found_agent=true
    fi
    
    if [[ -f "$GEMINI_FILE" ]]; then
        update_agent_file "$GEMINI_FILE" "Gemini CLI"
        found_agent=true
    fi
    
    if [[ -f "$COPILOT_FILE" ]]; then
        update_agent_file "$COPILOT_FILE" "GitHub Copilot"
        found_agent=true
    fi
    
    if [[ -f "$CURSOR_FILE" ]]; then
        update_agent_file "$CURSOR_FILE" "Cursor IDE"
        found_agent=true
    fi
    
    if [[ -f "$QWEN_FILE" ]]; then
        update_agent_file "$QWEN_FILE" "Qwen Code"
        found_agent=true
    fi
    
    if [[ -f "$AGENTS_FILE" ]]; then
        update_agent_file "$AGENTS_FILE" "Codex/opencode"
        found_agent=true
    fi
    
    if [[ -f "$WINDSURF_FILE" ]]; then
        update_agent_file "$WINDSURF_FILE" "Windsurf"
        found_agent=true
    fi
    
    if [[ -f "$KILOCODE_FILE" ]]; then
        update_agent_file "$KILOCODE_FILE" "Kilo Code"
        found_agent=true
    fi

    if [[ -f "$AUGGIE_FILE" ]]; then
        update_agent_file "$AUGGIE_FILE" "Auggie CLI"
        found_agent=true
    fi
    
    if [[ -f "$ROO_FILE" ]]; then
        update_agent_file "$ROO_FILE" "Roo Code"
        found_agent=true
    fi

    if [[ -f "$CODEBUDDY_FILE" ]]; then
        update_agent_file "$CODEBUDDY_FILE" "CodeBuddy"
        found_agent=true
    fi

    if [[ -f "$Q_FILE" ]]; then
        update_agent_file "$Q_FILE" "Amazon Q Developer CLI"
        found_agent=true
    fi
    
    # Если файлов агентов нет, создаём файл Claude по умолчанию
    if [[ "$found_agent" == false ]]; then
        log_info "Файлы агентов не найдены. Создаём файл Claude по умолчанию..."
        update_agent_file "$CLAUDE_FILE" "Claude Code"
    fi
}
print_summary() {
    echo
    log_info "Итоги изменений:"
    
    if [[ -n "$NEW_LANG" ]]; then
        echo "  - Добавлен язык: $NEW_LANG"
    fi
    
    if [[ -n "$NEW_FRAMEWORK" ]]; then
        echo "  - Добавлен фреймворк: $NEW_FRAMEWORK"
    fi
    
    if [[ -n "$NEW_DB" ]] && [[ "$NEW_DB" != "N/A" ]]; then
        echo "  - Добавлена база данных: $NEW_DB"
    fi
    
    echo

    log_info "Использование: $0 [claude|gemini|copilot|cursor-agent|qwen|opencode|codex|windsurf|kilocode|auggie|codebuddy|q]"
}

#==============================================================================
# Основной сценарий
#==============================================================================

main() {
    # Проверяем окружение перед выполнением
    validate_environment
    
    log_info "=== Обновление контекстов агентов для фичи $CURRENT_BRANCH ==="
    
    # Разбираем план, чтобы извлечь данные проекта
    if ! parse_plan_data "$NEW_PLAN"; then
        log_error "Не удалось разобрать данные плана"
        exit 1
    fi
    
    # Выбираем сценарий обработки в зависимости от параметра агента
    local success=true
    
    if [[ -z "$AGENT_TYPE" ]]; then
        # Параметр не указан — обновляем все найденные файлы агентов
        log_info "Тип агента не задан, обновляем все доступные файлы..."
        if ! update_all_existing_agents; then
            success=false
        fi
    else
        # Передан конкретный агент — обновляем только его
        log_info "Обновляется агент: $AGENT_TYPE"
        if ! update_specific_agent "$AGENT_TYPE"; then
            success=false
        fi
    fi
    
    # Выводим суммарную информацию
    print_summary
    
    if [[ "$success" == true ]]; then
        log_success "Контексты агентов успешно обновлены"
        exit 0
    else
        log_error "Обновление контекстов агентов завершилось с ошибками"
        exit 1
    fi
}

# Запускаем main, если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
