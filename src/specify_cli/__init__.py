#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "typer",
#     "rich",
#     "platformdirs",
#     "readchar",
#     "httpx",
# ]
# ///
"""
Specify-ru CLI — инструмент для подготовки проектов по методологии Spec-Driven Development.

Использование:
    uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify-ru init <имя-проекта>
    uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify-ru init .
    uvx --from git+https://github.com/zemlyanin7/spec-kit-ru.git specify-ru init --here

Или установите глобально:
    uv tool install specify-ru-cli --from git+https://github.com/zemlyanin7/spec-kit-ru.git
    specify-ru init <имя-проекта>
    specify-ru init .
    specify-ru init --here
"""

import os
import subprocess
import sys
import zipfile
import tempfile
import shutil
import shlex
import json
from pathlib import Path
from typing import Optional, Tuple

import typer
import httpx
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.text import Text
from rich.live import Live
from rich.align import Align
from rich.table import Table
from rich.tree import Tree
from typer.core import TyperGroup

# For cross-platform keyboard input
import readchar
import ssl
import truststore

ssl_context = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
client = httpx.Client(verify=ssl_context)

def _github_token(cli_token: str | None = None) -> str | None:
    """Return sanitized GitHub token (cli arg takes precedence) or None."""
    return ((cli_token or os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN") or "").strip()) or None

def _github_auth_headers(cli_token: str | None = None) -> dict:
    """Return Authorization header dict only when a non-empty token exists."""
    token = _github_token(cli_token)
    return {"Authorization": f"Bearer {token}"} if token else {}

# Agent configuration with name, folder, install URL, and CLI tool requirement
AGENT_CONFIG = {
    "copilot": {
        "name": "GitHub Copilot",
        "folder": ".github/",
        "install_url": None,  # IDE-based, no CLI check needed
        "requires_cli": False,
    },
    "claude": {
        "name": "Claude Code",
        "folder": ".claude/",
        "install_url": "https://docs.anthropic.com/en/docs/claude-code/setup",
        "requires_cli": True,
    },
    "gemini": {
        "name": "Gemini CLI",
        "folder": ".gemini/",
        "install_url": "https://github.com/google-gemini/gemini-cli",
        "requires_cli": True,
    },
    "cursor-agent": {
        "name": "Cursor",
        "folder": ".cursor/",
        "install_url": None,  # IDE-based
        "requires_cli": False,
    },
    "qwen": {
        "name": "Qwen Code",
        "folder": ".qwen/",
        "install_url": "https://github.com/QwenLM/qwen-code",
        "requires_cli": True,
    },
    "opencode": {
        "name": "opencode",
        "folder": ".opencode/",
        "install_url": "https://opencode.ai",
        "requires_cli": True,
    },
    "codex": {
        "name": "Codex CLI",
        "folder": ".codex/",
        "install_url": "https://github.com/openai/codex",
        "requires_cli": True,
    },
    "windsurf": {
        "name": "Windsurf",
        "folder": ".windsurf/",
        "install_url": None,  # IDE-based
        "requires_cli": False,
    },
    "kilocode": {
        "name": "Kilo Code",
        "folder": ".kilocode/",
        "install_url": None,  # IDE-based
        "requires_cli": False,
    },
    "auggie": {
        "name": "Auggie CLI",
        "folder": ".augment/",
        "install_url": "https://docs.augmentcode.com/cli/setup-auggie/install-auggie-cli",
        "requires_cli": True,
    },
    "codebuddy": {
        "name": "CodeBuddy",
        "folder": ".codebuddy/",
        "install_url": "https://www.codebuddy.ai",
        "requires_cli": True,
    },
    "roo": {
        "name": "Roo Code",
        "folder": ".roo/",
        "install_url": None,  # IDE-based
        "requires_cli": False,
    },
    "q": {
        "name": "Amazon Q Developer CLI",
        "folder": ".amazonq/",
        "install_url": "https://aws.amazon.com/developer/learning/q-developer-cli/",
        "requires_cli": True,
    },
}

SCRIPT_TYPE_CHOICES = {"sh": "POSIX-оболочка (bash/zsh)", "ps": "PowerShell"}

CLAUDE_LOCAL_PATH = Path.home() / ".claude" / "local" / "claude"

BANNER = """
███████╗██████╗ ███████╗ ██████╗██╗███████╗██╗   ██╗
██╔════╝██╔══██╗██╔════╝██╔════╝██║██╔════╝╚██╗ ██╔╝
███████╗██████╔╝█████╗  ██║     ██║█████╗   ╚████╔╝ 
╚════██║██╔═══╝ ██╔══╝  ██║     ██║██╔══╝    ╚██╔╝  
███████║██║     ███████╗╚██████╗██║██║        ██║   
╚══════╝╚═╝     ╚══════╝ ╚═════╝╚═╝╚═╝        ╚═╝   
"""

TAGLINE = "GitHub Spec Kit — набор инструментов для разработки, управляемой спецификациями"
class StepTracker:
    """Отслеживает и отображает иерархию шагов без эмодзи в стиле дерева Claude Code.
    Поддерживает автообновление через привязанный коллбэк.
    """
    def __init__(self, title: str):
        self.title = title
        self.steps = []  # list of dicts: {key, label, status, detail}
        self.status_order = {"pending": 0, "running": 1, "done": 2, "error": 3, "skipped": 4}
        self._refresh_cb = None  # callable to trigger UI refresh

    def attach_refresh(self, cb):
        self._refresh_cb = cb

    def add(self, key: str, label: str):
        if key not in [s["key"] for s in self.steps]:
            self.steps.append({"key": key, "label": label, "status": "pending", "detail": ""})
            self._maybe_refresh()

    def start(self, key: str, detail: str = ""):
        self._update(key, status="running", detail=detail)

    def complete(self, key: str, detail: str = ""):
        self._update(key, status="done", detail=detail)

    def error(self, key: str, detail: str = ""):
        self._update(key, status="error", detail=detail)

    def skip(self, key: str, detail: str = ""):
        self._update(key, status="skipped", detail=detail)

    def _update(self, key: str, status: str, detail: str):
        for s in self.steps:
            if s["key"] == key:
                s["status"] = status
                if detail:
                    s["detail"] = detail
                self._maybe_refresh()
                return

        self.steps.append({"key": key, "label": key, "status": status, "detail": detail})
        self._maybe_refresh()

    def _maybe_refresh(self):
        if self._refresh_cb:
            try:
                self._refresh_cb()
            except Exception:
                pass

    def render(self):
        tree = Tree(f"[cyan]{self.title}[/cyan]", guide_style="grey50")
        for step in self.steps:
            label = step["label"]
            detail_text = step["detail"].strip() if step["detail"] else ""

            status = step["status"]
            if status == "done":
                symbol = "[green]●[/green]"
            elif status == "pending":
                symbol = "[green dim]○[/green dim]"
            elif status == "running":
                symbol = "[cyan]○[/cyan]"
            elif status == "error":
                symbol = "[red]●[/red]"
            elif status == "skipped":
                symbol = "[yellow]○[/yellow]"
            else:
                symbol = " "

            if status == "pending":
                # Entire line light gray (pending)
                if detail_text:
                    line = f"{symbol} [bright_black]{label} ({detail_text})[/bright_black]"
                else:
                    line = f"{symbol} [bright_black]{label}[/bright_black]"
            else:
                # Label white, detail (if any) light gray in parentheses
                if detail_text:
                    line = f"{symbol} [white]{label}[/white] [bright_black]({detail_text})[/bright_black]"
                else:
                    line = f"{symbol} [white]{label}[/white]"

            tree.add(line)
        return tree

def get_key():
    """Получить одиночное нажатие клавиши кроссплатформенно с помощью readchar."""
    key = readchar.readkey()

    if key == readchar.key.UP or key == readchar.key.CTRL_P:
        return 'up'
    if key == readchar.key.DOWN or key == readchar.key.CTRL_N:
        return 'down'

    if key == readchar.key.ENTER:
        return 'enter'

    if key == readchar.key.ESC:
        return 'escape'

    if key == readchar.key.CTRL_C:
        raise KeyboardInterrupt

    return key

def select_with_arrows(options: dict, prompt_text: str = "Выберите вариант", default_key: str = None) -> str:
    """
    Интерактивный выбор с помощью стрелок и Rich Live.
    
    Args:
        options: словарь, где ключи — идентификаторы вариантов, значения — описания
        prompt_text: текст, отображаемый над списком
        default_key: ключ варианта, подсвечиваемого по умолчанию
        
    Returns:
        Ключ выбранного варианта
    """
    option_keys = list(options.keys())
    if default_key and default_key in option_keys:
        selected_index = option_keys.index(default_key)
    else:
        selected_index = 0

    selected_key = None

    def create_selection_panel():
        """Создать панель выбора с подсвеченным текущим вариантом."""
        table = Table.grid(padding=(0, 2))
        table.add_column(style="cyan", justify="left", width=3)
        table.add_column(style="white", justify="left")

        for i, key in enumerate(option_keys):
            if i == selected_index:
                table.add_row("▶", f"[cyan]{key}[/cyan] [dim]({options[key]})[/dim]")
            else:
                table.add_row(" ", f"[cyan]{key}[/cyan] [dim]({options[key]})[/dim]")

        table.add_row("", "")
        table.add_row("", "[dim]Используйте ↑/↓ для навигации, Enter для выбора, Esc — отмена[/dim]")

        return Panel(
            table,
            title=f"[bold]{prompt_text}[/bold]",
            border_style="cyan",
            padding=(1, 2)
        )

    console.print()

    def run_selection_loop():
        nonlocal selected_key, selected_index
        with Live(create_selection_panel(), console=console, transient=True, auto_refresh=False) as live:
            while True:
                try:
                    key = get_key()
                    if key == 'up':
                        selected_index = (selected_index - 1) % len(option_keys)
                    elif key == 'down':
                        selected_index = (selected_index + 1) % len(option_keys)
                    elif key == 'enter':
                        selected_key = option_keys[selected_index]
                        break
                    elif key == 'escape':
                        console.print("\n[yellow]Выбор отменён[/yellow]")
                        raise typer.Exit(1)

                    live.update(create_selection_panel(), refresh=True)

                except KeyboardInterrupt:
                    console.print("\n[yellow]Выбор отменён[/yellow]")
                    raise typer.Exit(1)

    run_selection_loop()

    if selected_key is None:
        console.print("\n[red]Не удалось выполнить выбор.[/red]")
        raise typer.Exit(1)

    return selected_key

console = Console()

class BannerGroup(TyperGroup):
    """Группа команд Typer, которая показывает баннер перед справкой."""

    def format_help(self, ctx, formatter):
        # Show banner before help
        show_banner()
        super().format_help(ctx, formatter)


app = typer.Typer(
    name="specify-ru",
    help="Инструмент подготовки проектов по методологии Spec-Driven Development",
    add_completion=False,
    invoke_without_command=True,
    cls=BannerGroup,
)

def show_banner():
    """Показать ASCII‑баннер."""
    banner_lines = BANNER.strip().split('\n')
    colors = ["bright_blue", "blue", "cyan", "bright_cyan", "white", "bright_white"]

    styled_banner = Text()
    for i, line in enumerate(banner_lines):
        color = colors[i % len(colors)]
        styled_banner.append(line + "\n", style=color)

    console.print(Align.center(styled_banner))
    console.print(Align.center(Text(TAGLINE, style="italic bright_yellow")))
    console.print()

@app.callback()
def callback(ctx: typer.Context):
    """Показывать баннер, если команда вызвана без подкоманд."""
    if ctx.invoked_subcommand is None and "--help" not in sys.argv and "-h" not in sys.argv:
        show_banner()
        console.print(Align.center("[dim]Введите 'specify-ru --help', чтобы увидеть справку[/dim]"))
        console.print()

def run_command(cmd: list[str], check_return: bool = True, capture: bool = False, shell: bool = False) -> Optional[str]:
    """Выполнить shell-команду и при необходимости получить её вывод."""
    try:
        if capture:
            result = subprocess.run(cmd, check=check_return, capture_output=True, text=True, shell=shell)
            return result.stdout.strip()
        else:
            subprocess.run(cmd, check=check_return, shell=shell)
            return None
    except subprocess.CalledProcessError as e:
        if check_return:
            console.print(f"[red]Ошибка при выполнении команды:[/red] {' '.join(cmd)}")
            console.print(f"[red]Код завершения:[/red] {e.returncode}")
            if hasattr(e, 'stderr') and e.stderr:
                console.print(f"[red]Сообщение об ошибке:[/red] {e.stderr}")
            raise
        return None

def check_tool(tool: str, tracker: StepTracker = None) -> bool:
    """Проверить, установлен ли инструмент. При необходимости обновить трекер.
    
    Args:
        tool: название проверяемого инструмента
        tracker: необязательный StepTracker для обновления статуса
        
    Returns:
        True, если инструмент найден, иначе False
    """
    # Special handling for Claude CLI after `claude migrate-installer`
    # See: https://github.com/github/spec-kit/issues/123
    # The migrate-installer command REMOVES the original executable from PATH
    # and creates an alias at ~/.claude/local/claude instead
    # This path should be prioritized over other claude executables in PATH
    if tool == "claude":
        if CLAUDE_LOCAL_PATH.exists() and CLAUDE_LOCAL_PATH.is_file():
            if tracker:
                tracker.complete(tool, "доступен")
            return True
    
    found = shutil.which(tool) is not None
    
    if tracker:
        if found:
            tracker.complete(tool, "доступен")
        else:
            tracker.error(tool, "не найден")
    
    return found

def is_git_repo(path: Path = None) -> bool:
    """Проверить, находится ли указанный путь внутри git-репозитория."""
    if path is None:
        path = Path.cwd()
    
    if not path.is_dir():
        return False

    try:
        # Use git command to check if inside a work tree
        subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            check=True,
            capture_output=True,
            cwd=path,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def init_git_repo(project_path: Path, quiet: bool = False) -> Tuple[bool, Optional[str]]:
    """Инициализировать git-репозиторий в указанном пути.
    
    Args:
        project_path: каталог, где нужно создать репозиторий
        quiet: если True, подавлять вывод (статус ведёт трекер)
    
    Returns:
        Кортеж вида (успешно: bool, сообщение об ошибке: Optional[str])
    """
    try:
        original_cwd = Path.cwd()
        os.chdir(project_path)
        if not quiet:
            console.print("[cyan]Инициализируем git-репозиторий...[/cyan]")
        subprocess.run(["git", "init"], check=True, capture_output=True, text=True)
        subprocess.run(["git", "add", "."], check=True, capture_output=True, text=True)
        subprocess.run(["git", "commit", "-m", "Initial commit from Specify template"], check=True, capture_output=True, text=True)
        if not quiet:
            console.print("[green]✓[/green] Git-репозиторий создан")
        return True, None

    except subprocess.CalledProcessError as e:
        error_msg = f"Command: {' '.join(e.cmd)}\nExit code: {e.returncode}"
        if e.stderr:
            error_msg += f"\nОшибка: {e.stderr.strip()}"
        elif e.stdout:
            error_msg += f"\nВывод: {e.stdout.strip()}"
        
        if not quiet:
            console.print(f"[red]Ошибка при инициализации git-репозитория:[/red] {e}")
        return False, error_msg
    finally:
        os.chdir(original_cwd)

def download_template_from_github(ai_assistant: str, download_dir: Path, *, script_type: str = "sh", verbose: bool = True, show_progress: bool = True, client: httpx.Client = None, debug: bool = False, github_token: str = None) -> Tuple[Path, dict]:
    repo_owner = "zemlyanin7"
    repo_name = "spec-kit-ru"
    if client is None:
        client = httpx.Client(verify=ssl_context)

    if verbose:
        console.print("[cyan]Получаем информацию о последнем релизе...[/cyan]")
    api_url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/releases/latest"

    try:
        response = client.get(
            api_url,
            timeout=30,
            follow_redirects=True,
            headers=_github_auth_headers(github_token),
        )
        status = response.status_code
        if status != 200:
            msg = f"GitHub API returned {status} for {api_url}"
            if debug:
                msg += f"\nResponse headers: {response.headers}\nBody (truncated 500): {response.text[:500]}"
            raise RuntimeError(msg)
        try:
            release_data = response.json()
        except ValueError as je:
            raise RuntimeError(f"Не удалось разобрать JSON релиза: {je}\nRaw (truncated 400): {response.text[:400]}")
    except Exception as e:
        console.print(f"[red]Ошибка при получении информации о релизе[/red]")
        console.print(Panel(str(e), title="Ошибка запроса", border_style="red"))
        raise typer.Exit(1)

    assets = release_data.get("assets", [])
    pattern = f"spec-kit-template-{ai_assistant}-{script_type}"
    matching_assets = [
        asset for asset in assets
        if pattern in asset["name"] and asset["name"].endswith(".zip")
    ]

    asset = matching_assets[0] if matching_assets else None

    if asset is None:
        console.print(f"[red]Подходящий файл релиза не найден[/red] для [bold]{ai_assistant}[/bold] (ожидался шаблон: [bold]{pattern}[/bold])")
        asset_names = [a.get('name', '?') for a in assets]
        console.print(Panel("\n".join(asset_names) or "(нет артефактов)", title="Доступные артефакты", border_style="yellow"))
        raise typer.Exit(1)

    download_url = asset["browser_download_url"]
    filename = asset["name"]
    file_size = asset["size"]

    if verbose:
        console.print(f"[cyan]Найден шаблон:[/cyan] {filename}")
        console.print(f"[cyan]Размер:[/cyan] {file_size:,} байт")
        console.print(f"[cyan]Релиз:[/cyan] {release_data['tag_name']}")

    zip_path = download_dir / filename
    if verbose:
        console.print(f"[cyan]Скачиваем шаблон...[/cyan]")

    try:
        with client.stream(
            "GET",
            download_url,
            timeout=60,
            follow_redirects=True,
            headers=_github_auth_headers(github_token),
        ) as response:
            if response.status_code != 200:
                body_sample = response.text[:400]
                raise RuntimeError(f"Скачивание завершилось с кодом {response.status_code}\nHeaders: {response.headers}\nBody (truncated): {body_sample}")
            total_size = int(response.headers.get('content-length', 0))
            with open(zip_path, 'wb') as f:
                if total_size == 0:
                    for chunk in response.iter_bytes(chunk_size=8192):
                        f.write(chunk)
                else:
                    if show_progress:
                        with Progress(
                            SpinnerColumn(),
                            TextColumn("[progress.description]{task.description}"),
                            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                            console=console,
                        ) as progress:
                            task = progress.add_task("Скачивание...", total=total_size)
                            downloaded = 0
                            for chunk in response.iter_bytes(chunk_size=8192):
                                f.write(chunk)
                                downloaded += len(chunk)
                                progress.update(task, completed=downloaded)
                    else:
                        for chunk in response.iter_bytes(chunk_size=8192):
                            f.write(chunk)
    except Exception as e:
        console.print(f"[red]Ошибка при скачивании шаблона[/red]")
        detail = str(e)
        if zip_path.exists():
            zip_path.unlink()
        console.print(Panel(detail, title="Ошибка скачивания", border_style="red"))
        raise typer.Exit(1)
    if verbose:
        console.print(f"Скачано: {filename}")
    metadata = {
        "filename": filename,
        "size": file_size,
        "release": release_data["tag_name"],
        "asset_url": download_url
    }
    return zip_path, metadata

def download_and_extract_template(project_path: Path, ai_assistant: str, script_type: str, is_current_dir: bool = False, *, verbose: bool = True, tracker: StepTracker | None = None, client: httpx.Client = None, debug: bool = False, github_token: str = None) -> Path:
    """Скачать последний релиз и распаковать его для создания проекта.
    Возвращает project_path. Если передан tracker, использует шаги fetch, download, extract, cleanup.
    """
    current_dir = Path.cwd()

    if tracker:
        tracker.start("fetch", "запрос к GitHub API")
    try:
        zip_path, meta = download_template_from_github(
            ai_assistant,
            current_dir,
            script_type=script_type,
            verbose=verbose and tracker is None,
            show_progress=(tracker is None),
            client=client,
            debug=debug,
            github_token=github_token
        )
        if tracker:
            tracker.complete("fetch", f"релиз {meta['release']} ({meta['size']:,} байт)")
            tracker.add("download", "Скачать шаблон")
            tracker.complete("download", meta['filename'])
    except Exception as e:
        if tracker:
            tracker.error("fetch", str(e))
        else:
            if verbose:
                console.print(f"[red]Ошибка при скачивании шаблона:[/red] {e}")
        raise

    if tracker:
        tracker.add("extract", "Распаковать шаблон")
        tracker.start("extract")
    elif verbose:
        console.print("Распаковываем шаблон...")

    try:
        if not is_current_dir:
            project_path.mkdir(parents=True)

        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_contents = zip_ref.namelist()
            if tracker:
                tracker.start("zip-list")
                tracker.complete("zip-list", f"{len(zip_contents)} элементов")
            elif verbose:
                console.print(f"[cyan]ZIP-архив содержит {len(zip_contents)} элементов[/cyan]")

            if is_current_dir:
                with tempfile.TemporaryDirectory() as temp_dir:
                    temp_path = Path(temp_dir)
                    zip_ref.extractall(temp_path)

                    extracted_items = list(temp_path.iterdir())
                    if tracker:
                        tracker.start("extracted-summary")
                        tracker.complete("extracted-summary", f"временный каталог: {len(extracted_items)} элементов")
                    elif verbose:
                        console.print(f"[cyan]Распаковано {len(extracted_items)} элементов во временный каталог[/cyan]")

                    source_dir = temp_path
                    if len(extracted_items) == 1 and extracted_items[0].is_dir():
                        source_dir = extracted_items[0]
                        if tracker:
                            tracker.add("flatten", "Убрать лишний уровень вложенности")
                            tracker.complete("flatten")
                        elif verbose:
                            console.print(f"[cyan]Обнаружена вложенная структура каталогов[/cyan]")

                    for item in source_dir.iterdir():
                        dest_path = project_path / item.name
                        if item.is_dir():
                            if dest_path.exists():
                                if verbose and not tracker:
                                    console.print(f"[yellow]Объединяем каталог:[/yellow] {item.name}")
                                for sub_item in item.rglob('*'):
                                    if sub_item.is_file():
                                        rel_path = sub_item.relative_to(item)
                                        dest_file = dest_path / rel_path
                                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                                        shutil.copy2(sub_item, dest_file)
                            else:
                                shutil.copytree(item, dest_path)
                        else:
                            if dest_path.exists() and verbose and not tracker:
                                console.print(f"[yellow]Перезаписываем файл:[/yellow] {item.name}")
                            shutil.copy2(item, dest_path)
                    if verbose and not tracker:
                        console.print(f"[cyan]Файлы шаблона объединены с текущим каталогом[/cyan]")
            else:
                zip_ref.extractall(project_path)

                extracted_items = list(project_path.iterdir())
                if tracker:
                    tracker.start("extracted-summary")
                    tracker.complete("extracted-summary", f"{len(extracted_items)} элементов верхнего уровня")
                elif verbose:
                    console.print(f"[cyan]Распаковано {len(extracted_items)} элементов в {project_path}:[/cyan]")
                    for item in extracted_items:
                        console.print(f"  - {item.name} ({'каталог' if item.is_dir() else 'файл'})")

                if len(extracted_items) == 1 and extracted_items[0].is_dir():
                    nested_dir = extracted_items[0]
                    temp_move_dir = project_path.parent / f"{project_path.name}_temp"

                    shutil.move(str(nested_dir), str(temp_move_dir))

                    project_path.rmdir()

                    shutil.move(str(temp_move_dir), str(project_path))
                    if tracker:
                        tracker.add("flatten", "Убрать лишний уровень вложенности")
                        tracker.complete("flatten")
                    elif verbose:
                        console.print(f"[cyan]Убрана вложенная структура каталогов[/cyan]")

    except Exception as e:
        if tracker:
            tracker.error("extract", str(e))
        else:
            if verbose:
                console.print(f"[red]Ошибка при распаковке шаблона:[/red] {e}")
                if debug:
                    console.print(Panel(str(e), title="Ошибка распаковки", border_style="red"))

        if not is_current_dir and project_path.exists():
            shutil.rmtree(project_path)
        raise typer.Exit(1)
    else:
        if tracker:
            tracker.complete("extract")
    finally:
        if tracker:
            tracker.add("cleanup", "Удалить временный архив")

        if zip_path.exists():
            zip_path.unlink()
            if tracker:
                tracker.complete("cleanup")
            elif verbose:
                console.print(f"Удалено: {zip_path.name}")

    return project_path


def ensure_executable_scripts(project_path: Path, tracker: StepTracker | None = None) -> None:
    """Убедиться, что POSIX-скрипты .sh в .specify/scripts рекурсивно имеют права на выполнение (на Windows пропускается)."""
    if os.name == "nt":
        return  # Windows: skip silently
    scripts_root = project_path / ".specify" / "scripts"
    if not scripts_root.is_dir():
        return
    failures: list[str] = []
    updated = 0
    for script in scripts_root.rglob("*.sh"):
        try:
            if script.is_symlink() or not script.is_file():
                continue
            try:
                with script.open("rb") as f:
                    if f.read(2) != b"#!":
                        continue
            except Exception:
                continue
            st = script.stat(); mode = st.st_mode
            if mode & 0o111:
                continue
            new_mode = mode
            if mode & 0o400: new_mode |= 0o100
            if mode & 0o040: new_mode |= 0o010
            if mode & 0o004: new_mode |= 0o001
            if not (new_mode & 0o100):
                new_mode |= 0o100
            os.chmod(script, new_mode)
            updated += 1
        except Exception as e:
            failures.append(f"{script.relative_to(scripts_root)}: {e}")
    if tracker:
        detail = f"{updated} обновлено" + (f", {len(failures)} не удалось" if failures else "")
        tracker.add("chmod", "Назначить права на выполнение рекурсивно")
        (tracker.error if failures else tracker.complete)("chmod", detail)
    else:
        if updated:
            console.print(f"[cyan]Добавлены права на выполнение для {updated} скриптов (рекурсивно)[/cyan]")
        if failures:
            console.print("[yellow]Не удалось обновить некоторые скрипты:[/yellow]")
            for f in failures:
                console.print(f"  - {f}")

@app.command()
def init(
    project_name: str = typer.Argument(None, help="Имя каталога для нового проекта (необязательно при использовании --here; можно указать '.' для текущего каталога)"),
    ai_assistant: str = typer.Option(None, "--ai", help="Выбранный ИИ-агент: claude, gemini, copilot, cursor-agent, qwen, opencode, codex, windsurf, kilocode, auggie, codebuddy или q"),
    script_type: str = typer.Option(None, "--script", help="Тип генерируемых скриптов: sh или ps"),
    ignore_agent_tools: bool = typer.Option(False, "--ignore-agent-tools", help="Пропустить проверку наличия CLI для выбранного ИИ-агента"),
    no_git: bool = typer.Option(False, "--no-git", help="Не инициализировать git-репозиторий"),
    here: bool = typer.Option(False, "--here", help="Инициализировать проект в текущем каталоге"),
    force: bool = typer.Option(False, "--force", help="Принудительно объединить файлы при использовании --here (без подтверждения)"),
    skip_tls: bool = typer.Option(False, "--skip-tls", help="Отключить проверку SSL/TLS (не рекомендуется)"),
    debug: bool = typer.Option(False, "--debug", help="Показать расширенную диагностику для сетевых ошибок и ошибок распаковки"),
    github_token: str = typer.Option(None, "--github-token", help="Токен GitHub для API-запросов (или используйте переменные GH_TOKEN/GITHUB_TOKEN)"),
):
    """
    Инициализировать новый проект Specify на основе последнего шаблона.
    
    Команда выполняет:
    1. Проверку необходимых инструментов (git необязателен)
    2. Выбор ИИ-агента
    3. Скачивание подходящего шаблона из GitHub
    4. Распаковку в новый каталог или в текущий каталог
    5. Инициализацию git-репозитория (если не указан --no-git и нет существующего)
    6. Настройку команд для ИИ-агента (при необходимости)
    
    Примеры:
        specify-ru init my-project
        specify-ru init my-project --ai claude
        specify-ru init my-project --ai copilot --no-git
        specify-ru init --ignore-agent-tools my-project
        specify-ru init . --ai claude         # Инициализация в текущем каталоге
        specify-ru init .                     # Текущий каталог (интерактивный выбор ИИ)
        specify-ru init --here --ai claude    # Альтернативный синтаксис для текущего каталога
        specify-ru init --here --ai codex
        specify-ru init --here --ai codebuddy
        specify-ru init --here
        specify-ru init --here --force        # Пропустить подтверждение, если каталог не пуст
    """

    show_banner()

    if project_name == ".":
        here = True
        project_name = None  # Clear project_name to use existing validation logic

    if here and project_name:
        console.print("[red]Ошибка:[/red] Нельзя одновременно задать имя проекта и использовать флаг --here")
        raise typer.Exit(1)

    if not here and not project_name:
        console.print("[red]Ошибка:[/red] Укажите имя проекта, используйте '.' для текущего каталога или передайте флаг --here")
        raise typer.Exit(1)

    if here:
        project_name = Path.cwd().name
        project_path = Path.cwd()

        existing_items = list(project_path.iterdir())
        if existing_items:
            console.print(f"[yellow]Предупреждение:[/yellow] Текущий каталог не пуст ({len(existing_items)} элементов)")
            console.print("[yellow]Файлы шаблона будут объединены с существующим содержимым и могут перезаписать файлы[/yellow]")
            if force:
                console.print("[cyan]Флаг --force: подтверждение пропущено, продолжаем объединение[/cyan]")
            else:
                response = typer.confirm("Продолжить?", default=True)
                if not response:
                    console.print("[yellow]Операция отменена[/yellow]")
                    raise typer.Exit(0)
    else:
        project_path = Path(project_name).resolve()
        if project_path.exists():
            error_panel = Panel(
                f"Каталог '[cyan]{project_name}[/cyan]' уже существует\n"
                "Выберите другое имя проекта или удалите существующий каталог.",
                title="[red]Конфликт каталогов[/red]",
                border_style="red",
                padding=(1, 2)
            )
            console.print()
            console.print(error_panel)
            raise typer.Exit(1)

    current_dir = Path.cwd()

    setup_lines = [
        "[cyan]Подготовка проекта Specify[/cyan]",
        "",
        f"{'Проект':<15} [green]{project_path.name}[/green]",
        f"{'Рабочий путь':<15} [dim]{current_dir}[/dim]",
    ]

    if not here:
        setup_lines.append(f"{'Каталог вывода':<15} [dim]{project_path}[/dim]")

    console.print(Panel("\n".join(setup_lines), border_style="cyan", padding=(1, 2)))

    should_init_git = False
    if not no_git:
        should_init_git = check_tool("git")
        if not should_init_git:
            console.print("[yellow]Git не найден — инициализация репозитория будет пропущена[/yellow]")

    if ai_assistant:
        if ai_assistant not in AGENT_CONFIG:
            console.print(f"[red]Ошибка:[/red] Некорректный ИИ-агент '{ai_assistant}'. Допустимые значения: {', '.join(AGENT_CONFIG.keys())}")
            raise typer.Exit(1)
        selected_ai = ai_assistant
    else:
        # Create options dict for selection (agent_key: display_name)
        ai_choices = {key: config["name"] for key, config in AGENT_CONFIG.items()}
        selected_ai = select_with_arrows(
            ai_choices,
            "Выберите ИИ-агента:",
            "copilot"
        )

    if not ignore_agent_tools:
        agent_config = AGENT_CONFIG.get(selected_ai)
        if agent_config and agent_config["requires_cli"]:
            install_url = agent_config["install_url"]
            if not check_tool(selected_ai):
                error_panel = Panel(
                    f"[cyan]{selected_ai}[/cyan] не найден\n"
                    f"Установите его: [cyan]{install_url}[/cyan]\n"
                    f"{agent_config['name']} необходим для продолжения работы с этим типом проекта.\n\n"
                    "Подсказка: используйте [cyan]--ignore-agent-tools[/cyan], чтобы пропустить проверку",
                    title="[red]Ошибка обнаружения агента[/red]",
                    border_style="red",
                    padding=(1, 2)
                )
                console.print()
                console.print(error_panel)
                raise typer.Exit(1)

    if script_type:
        if script_type not in SCRIPT_TYPE_CHOICES:
            console.print(f"[red]Ошибка:[/red] Недопустимый тип скриптов '{script_type}'. Выберите один из: {', '.join(SCRIPT_TYPE_CHOICES.keys())}")
            raise typer.Exit(1)
        selected_script = script_type
    else:
        default_script = "ps" if os.name == "nt" else "sh"

        if sys.stdin.isatty():
            selected_script = select_with_arrows(SCRIPT_TYPE_CHOICES, "Выберите тип скриптов (или нажмите Enter)", default_script)
        else:
            selected_script = default_script

    console.print(f"[cyan]Выбранный ИИ-агент:[/cyan] {selected_ai}")
    console.print(f"[cyan]Тип скриптов:[/cyan] {selected_script}")

    tracker = StepTracker("Инициализация проекта Specify")

    sys._specify_tracker_active = True

    tracker.add("precheck", "Проверить инструменты")
    tracker.complete("precheck", "готово")
    tracker.add("ai-select", "Выбрать ИИ-агента")
    tracker.complete("ai-select", f"{selected_ai}")
    tracker.add("script-select", "Выбрать тип скриптов")
    tracker.complete("script-select", selected_script)
    for key, label in [
        ("fetch", "Получить релиз"),
        ("download", "Скачать шаблон"),
        ("extract", "Распаковать шаблон"),
        ("zip-list", "Содержимое архива"),
        ("extracted-summary", "Итог распаковки"),
        ("chmod", "Сделать скрипты исполняемыми"),
        ("cleanup", "Очистить временные файлы"),
        ("git", "Инициализировать git"),
        ("final", "Завершение")
    ]:
        tracker.add(key, label)

    # Track git error message outside Live context so it persists
    git_error_message = None

    with Live(tracker.render(), console=console, refresh_per_second=8, transient=True) as live:
        tracker.attach_refresh(lambda: live.update(tracker.render()))
        try:
            verify = not skip_tls
            local_ssl_context = ssl_context if verify else False
            local_client = httpx.Client(verify=local_ssl_context)

            download_and_extract_template(project_path, selected_ai, selected_script, here, verbose=False, tracker=tracker, client=local_client, debug=debug, github_token=github_token)

            ensure_executable_scripts(project_path, tracker=tracker)

            if not no_git:
                tracker.start("git")
                if is_git_repo(project_path):
                    tracker.complete("git", "обнаружен существующий репозиторий")
                elif should_init_git:
                    success, error_msg = init_git_repo(project_path, quiet=True)
                    if success:
                        tracker.complete("git", "инициализирован")
                    else:
                        tracker.error("git", "ошибка инициализации")
                        git_error_message = error_msg
                else:
                    tracker.skip("git", "git недоступен")
            else:
                tracker.skip("git", "флаг --no-git")

            tracker.complete("final", "проект готов")
        except Exception as e:
            tracker.error("final", str(e))
            console.print(Panel(f"Ошибка инициализации: {e}", title="Сбой", border_style="red"))
            if debug:
                _env_pairs = [
                    ("Python", sys.version.split()[0]),
                    ("Platform", sys.platform),
                    ("Текущий каталог", str(Path.cwd())),
                ]
                _label_width = max(len(k) for k, _ in _env_pairs)
                env_lines = [f"{k.ljust(_label_width)} → [bright_black]{v}[/bright_black]" for k, v in _env_pairs]
                console.print(Panel("\n".join(env_lines), title="Отладочная среда", border_style="magenta"))
            if not here and project_path.exists():
                shutil.rmtree(project_path)
            raise typer.Exit(1)
        finally:
            pass

    console.print(tracker.render())
    console.print("\n[bold green]Проект готов.[/bold green]")
    
    # Show git error details if initialization failed
    if git_error_message:
        console.print()
        git_error_panel = Panel(
            f"[yellow]Предупреждение:[/yellow] не удалось инициализировать git-репозиторий\n\n"
            f"{git_error_message}\n\n"
            f"[dim]Вы можете инициализировать git вручную позже с помощью:[/dim]\n"
            f"[cyan]cd {project_path if not here else '.'}[/cyan]\n"
            f"[cyan]git init[/cyan]\n"
            f"[cyan]git add .[/cyan]\n"
            f"[cyan]git commit -m \"Initial commit\"[/cyan]",
            title="[red]Сбой инициализации git[/red]",
            border_style="red",
            padding=(1, 2)
        )
        console.print(git_error_panel)

    # Agent folder security notice
    agent_config = AGENT_CONFIG.get(selected_ai)
    if agent_config:
        agent_folder = agent_config["folder"]
        security_notice = Panel(
            f"Некоторые агенты могут сохранять учётные данные, токены и другие приватные артефакты в своём каталоге внутри проекта.\n"
            f"Рекомендуем добавить [cyan]{agent_folder}[/cyan] (или его часть) в [cyan].gitignore[/cyan], чтобы избежать случайной утечки данных.",
            title="[yellow]Безопасность каталога агента[/yellow]",
            border_style="yellow",
            padding=(1, 2)
        )
        console.print()
        console.print(security_notice)

    steps_lines = []
    if not here:
        steps_lines.append(f"1. Перейдите в каталог проекта: [cyan]cd {project_name}[/cyan]")
        step_num = 2
    else:
        steps_lines.append("1. Вы уже находитесь в каталоге проекта!")
        step_num = 2

    # Add Codex-specific setup step if needed
    if selected_ai == "codex":
        codex_path = project_path / ".codex"
        quoted_path = shlex.quote(str(codex_path))
        if os.name == "nt":  # Windows
            cmd = f"setx CODEX_HOME {quoted_path}"
        else:  # Unix-like systems
            cmd = f"export CODEX_HOME={quoted_path}"
        
        steps_lines.append(f"{step_num}. Установите переменную окружения [cyan]CODEX_HOME[/cyan] перед запуском Codex: [cyan]{cmd}[/cyan]")
        step_num += 1

    steps_lines.append(f"{step_num}. Используйте slash-команды в своём ИИ-агенте:")

    steps_lines.append("   2.1 [cyan]/specify-ru.constitution[/] — зафиксировать конституцию проекта")
    steps_lines.append("   2.2 [cyan]/specify-ru.specify[/] — создать базовую спецификацию")
    steps_lines.append("   2.3 [cyan]/specify-ru.plan[/] — подготовить план реализации")
    steps_lines.append("   2.4 [cyan]/specify-ru.tasks[/] — сформировать список задач")
    steps_lines.append("   2.5 [cyan]/specify-ru.implement[/] — выполнить реализацию")

    steps_panel = Panel("\n".join(steps_lines), title="Следующие шаги", border_style="cyan", padding=(1,2))
    console.print()
    console.print(steps_panel)

    enhancement_lines = [
        "Дополнительные команды для улучшения спецификаций [bright_black](качество и уверенность)[/bright_black]",
        "",
        f"○ [cyan]/specify-ru.clarify[/] [bright_black](опционально)[/bright_black] — структурированные вопросы для прояснения неопределённостей до планирования (выполните до [cyan]/specify-ru.plan[/])",
        f"○ [cyan]/specify-ru.analyze[/] [bright_black](опционально)[/bright_black] — отчёт о согласованности артефактов (после [cyan]/specify-ru.tasks[/], перед [cyan]/specify-ru.implement[/])",
        f"○ [cyan]/specify-ru.checklist[/] [bright_black](опционально)[/bright_black] — чек-листы качества для проверки полноты и ясности требований (после [cyan]/specify-ru.plan[/])"
    ]
    enhancements_panel = Panel("\n".join(enhancement_lines), title="Дополнительные команды", border_style="cyan", padding=(1,2))
    console.print()
    console.print(enhancements_panel)

@app.command()
def check():
    """Проверить установку необходимых инструментов."""
    show_banner()
    console.print("[bold]Проверяем установленные инструменты...[/bold]\n")

    tracker = StepTracker("Проверка доступных инструментов")

    tracker.add("git", "Git (система контроля версий)")
    git_ok = check_tool("git", tracker=tracker)
    
    agent_results = {}
    for agent_key, agent_config in AGENT_CONFIG.items():
        agent_name = agent_config["name"]
        
        tracker.add(agent_key, agent_name)
        agent_results[agent_key] = check_tool(agent_key, tracker=tracker)
    
    # Check VS Code variants (not in agent config)
    tracker.add("code", "Visual Studio Code")
    code_ok = check_tool("code", tracker=tracker)

    tracker.add("code-insiders", "Visual Studio Code Insiders")
    code_insiders_ok = check_tool("code-insiders", tracker=tracker)

    console.print(tracker.render())

    console.print("\n[bold green]Specify-ru CLI готов к работе![/bold green]")

    if not git_ok:
        console.print("[dim]Совет: установите git для управления репозиторием[/dim]")

    if not any(agent_results.values()):
        console.print("[dim]Совет: установите ИИ-агента для полноценной работы[/dim]")

def main():
    app()

if __name__ == "__main__":
    main()
