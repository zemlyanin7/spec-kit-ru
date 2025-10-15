#!/usr/bin/env pwsh
# Подготовка плана реализации для фичи

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Выводим справку по запросу
if ($Help) {
    Write-Output "Использование: ./setup-plan.ps1 [-Json] [-Help]"
    Write-Output "  -Json     вывод в формате JSON"
    Write-Output "  -Help     показать эту справку"
    exit 0
}

# Подключаем общие функции
. "$PSScriptRoot/common.ps1"

# Получаем пути и переменные из общего модуля
$paths = Get-FeaturePathsEnv

# Проверяем, что находимся во фичевой ветке (для git-репозиториев)
if (-not (Test-FeatureBranch -Branch $paths.CURRENT_BRANCH -HasGit $paths.HAS_GIT)) { 
    exit 1 
}

# Гарантируем наличие каталога фичи
New-Item -ItemType Directory -Path $paths.FEATURE_DIR -Force | Out-Null

# Копируем шаблон плана при наличии, иначе создаём пустой файл
$template = Join-Path $paths.REPO_ROOT '.specify/templates/plan-template.md'
if (Test-Path $template) { 
    Copy-Item $template $paths.IMPL_PLAN -Force
    Write-Output "Скопирован шаблон плана в $($paths.IMPL_PLAN)"
} else {
    Write-Warning "Шаблон плана не найден по пути $template"
    # Создаём базовый файл плана, если шаблон отсутствует
    New-Item -ItemType File -Path $paths.IMPL_PLAN -Force | Out-Null
}

# Формируем вывод
if ($Json) {
    $result = [PSCustomObject]@{ 
        FEATURE_SPEC = $paths.FEATURE_SPEC
        IMPL_PLAN = $paths.IMPL_PLAN
        SPECS_DIR = $paths.FEATURE_DIR
        BRANCH = $paths.CURRENT_BRANCH
        HAS_GIT = $paths.HAS_GIT
    }
    $result | ConvertTo-Json -Compress
} else {
    Write-Output "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
    Write-Output "IMPL_PLAN: $($paths.IMPL_PLAN)"
    Write-Output "SPECS_DIR: $($paths.FEATURE_DIR)"
    Write-Output "BRANCH: $($paths.CURRENT_BRANCH)"
    Write-Output "HAS_GIT: $($paths.HAS_GIT)"
}
