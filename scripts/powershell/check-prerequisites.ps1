#!/usr/bin/env pwsh

# Унифицированная проверка предпосылок (PowerShell)
#
# Скрипт выполняет общую проверку условий для процесса Spec-Driven Development.
# Он объединяет функциональность, ранее распределённую по нескольким отдельным скриптам.
#
# Использование: ./check-prerequisites.ps1 [ПАРАМЕТРЫ]
#
# ПАРАМЕТРЫ:
#   -Json               вывод в формате JSON
#   -RequireTasks       требовать наличие tasks.md (этап реализации)
#   -IncludeTasks       включить tasks.md в список AVAILABLE_DOCS
#   -PathsOnly          выводить только пути (без проверки)
#   -Help, -h           показать справку

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RequireTasks,
    [switch]$IncludeTasks,
    [switch]$PathsOnly,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Выводим справку по запросу
if ($Help) {
    Write-Output @"
Использование: check-prerequisites.ps1 [ПАРАМЕТРЫ]

Единая проверка предпосылок для процесса Spec-Driven Development.

ПАРАМЕТРЫ:
  -Json               вывод в формате JSON
  -RequireTasks       требовать наличие tasks.md (этап реализации)
  -IncludeTasks       включить tasks.md в список AVAILABLE_DOCS
  -PathsOnly          выводить только пути (без проверки предпосылок)
  -Help, -h           показать эту справку

ПРИМЕРЫ:
  # Проверка предпосылок для задач (требуется plan.md)
  .\check-prerequisites.ps1 -Json
  
  # Проверка предпосылок реализации (нужны plan.md и tasks.md)
  .\check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
  
  # Получить только пути фичи (без проверки)
  .\check-prerequisites.ps1 -PathsOnly

"@
    exit 0
}

# Подключаем общие функции
. "$PSScriptRoot/common.ps1"

# Получаем пути фичи и валидируем ветку
$paths = Get-FeaturePathsEnv

if (-not (Test-FeatureBranch -Branch $paths.CURRENT_BRANCH -HasGit:$paths.HAS_GIT)) { 
    exit 1 
}

# В режиме PathsOnly выводим пути и завершаем (совместим с -Json)
if ($PathsOnly) {
    if ($Json) {
        [PSCustomObject]@{
            REPO_ROOT    = $paths.REPO_ROOT
            BRANCH       = $paths.CURRENT_BRANCH
            FEATURE_DIR  = $paths.FEATURE_DIR
            FEATURE_SPEC = $paths.FEATURE_SPEC
            IMPL_PLAN    = $paths.IMPL_PLAN
            TASKS        = $paths.TASKS
        } | ConvertTo-Json -Compress
    } else {
        Write-Output "REPO_ROOT: $($paths.REPO_ROOT)"
        Write-Output "BRANCH: $($paths.CURRENT_BRANCH)"
        Write-Output "FEATURE_DIR: $($paths.FEATURE_DIR)"
        Write-Output "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
        Write-Output "IMPL_PLAN: $($paths.IMPL_PLAN)"
        Write-Output "TASKS: $($paths.TASKS)"
    }
    exit 0
}

# Проверяем обязательные каталоги и файлы
if (-not (Test-Path $paths.FEATURE_DIR -PathType Container)) {
    Write-Output "ERROR: Каталог фичи не найден: $($paths.FEATURE_DIR)"
    Write-Output "Сначала выполните /specify-ru.specify, чтобы создать структуру фичи."
    exit 1
}

if (-not (Test-Path $paths.IMPL_PLAN -PathType Leaf)) {
    Write-Output "ERROR: plan.md не найден в $($paths.FEATURE_DIR)"
    Write-Output "Сначала выполните /specify-ru.plan, чтобы создать план реализации."
    exit 1
}

# Проверяем наличие tasks.md при необходимости
if ($RequireTasks -and -not (Test-Path $paths.TASKS -PathType Leaf)) {
    Write-Output "ERROR: tasks.md не найден в $($paths.FEATURE_DIR)"
    Write-Output "Сначала выполните /specify-ru.tasks, чтобы создать список задач."
    exit 1
}

# Формируем список доступных документов
$docs = @()

# Всегда проверяем эти необязательные документы
if (Test-Path $paths.RESEARCH) { $docs += 'research.md' }
if (Test-Path $paths.DATA_MODEL) { $docs += 'data-model.md' }

# Каталог contracts проверяем, только если он существует и не пустой
if ((Test-Path $paths.CONTRACTS_DIR) -and (Get-ChildItem -Path $paths.CONTRACTS_DIR -ErrorAction SilentlyContinue | Select-Object -First 1)) { 
    $docs += 'contracts/' 
}

if (Test-Path $paths.QUICKSTART) { $docs += 'quickstart.md' }

# Добавляем tasks.md, если запрошено и файл существует
if ($IncludeTasks -and (Test-Path $paths.TASKS)) { 
    $docs += 'tasks.md' 
}

# Формируем вывод
if ($Json) {
    # JSON-вывод
    [PSCustomObject]@{ 
        FEATURE_DIR = $paths.FEATURE_DIR
        AVAILABLE_DOCS = $docs 
    } | ConvertTo-Json -Compress
} else {
    # Текстовый вывод
    Write-Output "FEATURE_DIR:$($paths.FEATURE_DIR)"
    Write-Output "AVAILABLE_DOCS:"
    
    # Показываем статус каждого возможного документа
    Test-FileExists -Path $paths.RESEARCH -Description 'research.md' | Out-Null
    Test-FileExists -Path $paths.DATA_MODEL -Description 'data-model.md' | Out-Null
    Test-DirHasFiles -Path $paths.CONTRACTS_DIR -Description 'contracts/' | Out-Null
    Test-FileExists -Path $paths.QUICKSTART -Description 'quickstart.md' | Out-Null
    
    if ($IncludeTasks) {
        Test-FileExists -Path $paths.TASKS -Description 'tasks.md' | Out-Null
    }
}
