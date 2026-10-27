#!/usr/bin/env python3
"""Set up a first desktop configuration, with a prepared command for a TTY."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

from update import Update, active_compositors, installation_lock

ROOT = Path(__file__).resolve().parents[1]
UNITS = ("hyprstack-session.service", "hyprstack-vpn.service")
TERMINALS = ("kitty", "foot", "alacritty", "ghostty", "wezterm", "konsole", "xfce4-terminal", "gnome-terminal", "tilix", "xterm")
BROWSERS = ("firefox", "chromium", "brave", "brave-browser", "google-chrome", "vivaldi", "thorium-browser")


def application(value, label, candidates):
    if value is None:
        default = next((name for name in candidates if shutil.which(name)), "")
        if not sys.stdin.isatty():
            raise ValueError(f"Укажите {label} через параметр командной строки (см. --help).")
        value = input(f"{label}" + (f" [{default}]" if default else "") + ": ").strip() or default
    argv = shlex.split(value)
    if not argv or not shutil.which(argv[0]):
        raise ValueError(f"Приложение не найдено: {value!r}. Установите его или выберите другое.")
    return argv


def terminal_prefix(argv):
    """Arguments used when the launcher runs a command inside a terminal."""
    name = Path(argv[0]).name
    flags = {"alacritty": ["-e"], "ghostty": ["-e"], "konsole": ["-e"],
             "xfce4-terminal": ["-x"], "gnome-terminal": ["--"], "tilix": ["-e"],
             "xterm": ["-e"], "wezterm": ["start", "--"]}.get(name, [])
    return argv + flags


def lua_string(value):
    # JSON's ASCII control escapes are not Lua escapes. Quote bytes explicitly.
    return '"' + "".join('\\' + c if c in '\\"' else f"\\{ord(c):03d}" if ord(c) < 32 else c for c in value) + '"'


def validate_paths(layout, services):
    paths = [layout.config / "hypr", layout.config / "hyprstack", layout.state / "hyprstack/scheme.json"]
    if services:
        paths.extend(layout.config / "systemd/user" / name for name in UNITS)
    for root in (layout.home, layout.config, layout.data, layout.state):
        if not root.is_absolute() or root == Path("/") or ".." in root.parts:
            raise ValueError("XDG-пути должны быть абсолютными пользовательскими каталогами: " + str(root))
    for path in paths:
        for parent in path.parents:
            if parent.is_symlink():
                raise ValueError("Родительский каталог управляется ссылкой: " + str(parent) + ". Используйте свой менеджер dotfiles.")
            if parent.exists() and not parent.is_dir():
                raise ValueError("Ожидался каталог: " + str(parent))
    # Moving one destination must never hide another destination or the sources.
    for path in paths:
        if ROOT.is_relative_to(path):
            raise ValueError("Исходники находятся внутри заменяемого каталога: " + str(path))
        for other in paths:
            if path != other and other.is_relative_to(path):
                raise ValueError("Каталоги установки пересекаются: " + str(path))


def prepare(layout, terminal, browser, services):
    # A fixed HOME-relative path is easy to enter in any login shell. Preserve
    # graphical-session XDG values rather than guessing them after logging out.
    directory = layout.home / ".local/state/hyprstack-setup"
    if any(path.is_symlink() for path in (directory, *directory.parents)):
        raise ValueError("Каталог подготовки управляется ссылкой: " + str(directory))
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    lines = ["#!/usr/bin/env bash", "set -euo pipefail"]
    for name, value in (("XDG_CONFIG_HOME", layout.config), ("XDG_DATA_HOME", layout.data),
                        ("XDG_STATE_HOME", layout.state),
                        ("XDG_CACHE_HOME", os.environ.get("XDG_CACHE_HOME") or layout.home / ".cache")):
        lines.append("export " + name + "=" + shlex.quote(str(value)))
    lines.append("export PATH=" + shlex.quote(os.environ["PATH"]))
    command = ["bash", str(ROOT / "configure.sh"), "--terminal", shlex.join(terminal), "--browser", shlex.join(browser)]
    if not services:
        command.append("--no-services")
    lines.append("exec " + shlex.join(command))
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".apply-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write("\n".join(lines) + "\n")
        os.chmod(temporary, 0o700)
        os.replace(temporary, directory / "apply.sh")
    finally:
        Path(temporary).unlink(missing_ok=True)
    print("Выбор приложений и XDG-пути сохранены. Конфигурация ещё не изменена.")
    print("Завершите сеанс Hyprland, войдите в TTY (Ctrl+Alt+F3) и выполните одну команду:")
    print("bash ~/.local/state/hyprstack-setup/apply.sh")


def stage_configuration(directory, layout, terminal, browser, services):
    hypr, settings = directory / "hypr", directory / "hyprstack"
    shutil.copytree(ROOT / "shell/assets/hyprland/config", hypr)
    shutil.copytree(ROOT / "distribution/defaults/hyprstack", settings)
    path = settings / "hypr-vars.lua"
    content = path.read_text()
    content = content.replace('terminal = "kitty",', "terminal = " + lua_string(shlex.join(terminal)) + ",")
    content = content.replace('browser = "firefox",', "browser = " + lua_string(shlex.join(browser)) + ",")
    path.write_text(content)
    path = settings / "shell.json"
    prefs = json.loads(path.read_text())
    prefs["general"]["apps"]["terminal"] = terminal_prefix(terminal)
    path.write_text(json.dumps(prefs, ensure_ascii=False, indent=2) + "\n")
    targets = [(hypr, layout.config / "hypr"), (settings, layout.config / "hyprstack")]
    for name in UNITS if services else ():
        source = directory / name
        shutil.copyfile(ROOT / "distribution/systemd/user" / name, source)
        targets.append((source, layout.config / "systemd/user" / name))

    # Generate initial colours without applying GTK/Qt/terminal settings to the
    # desktop from which setup is run. Theme sync starts with the new session.
    sys.path.insert(0, str(ROOT / "shell/assets"))
    import theme_manager as themes
    scheme_path = layout.state / "hyprstack/scheme.json"
    if scheme_path.exists():
        scheme = json.loads(scheme_path.read_text())
        colours = themes.validate_colours(scheme["colours"], scheme["mode"])
    else:
        theme = next(item for item in themes.builtins() if item["id"] == "hyprstack-catppuccin")
        variant = next(item for item in theme["variants"] if item["mode"] == "dark")
        colours = variant["colours"]
        scheme = {"name": theme["id"], "flavour": variant["flavour"], "mode": "dark", "accent": variant["accent"],
                  "variant": "tonalspot", "colours": colours, "paletteVersion": themes.PALETTE_VERSION}
        source = directory / "scheme.json"
        source.write_text(json.dumps(scheme, indent=2) + "\n")
        targets.append((source, scheme_path))
    (hypr / "scheme/current.lua").write_text("return {\n" + "".join(f'    {key} = "{value}",\n' for key, value in colours.items()) + "}\n")
    return targets


def remove(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def apply_configuration(layout, terminal, browser, services):
    # Stage every input before moving any existing configuration. Keep the
    # backup on the same filesystem as the replaced files (rename, not copy).
    layout.config.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".hyprstack-setup-", dir=layout.config) as directory:
        targets = stage_configuration(Path(directory), layout, terminal, browser, services)
        backup = None
        saved, installed = [], []
        try:
            for source, destination in targets:
                if destination.exists() or destination.is_symlink():
                    if backup is None:
                        backup = Path(tempfile.mkdtemp(prefix="hyprstack-backup.", dir=layout.config))
                        backup.chmod(0o700)
                    relative = destination.relative_to(layout.config)
                    previous = backup / relative
                    previous.parent.mkdir(parents=True, exist_ok=True)
                    destination.rename(previous)
                    saved.append((previous, destination))
                destination.parent.mkdir(parents=True, exist_ok=True)
                installed.append(destination)
                if source.is_dir():
                    shutil.copytree(source, destination)
                else:
                    shutil.copyfile(source, destination)
        except BaseException:
            for destination in reversed(installed):
                remove(destination)
            for previous, destination in reversed(saved):
                previous.rename(destination)
            if backup is not None:
                shutil.rmtree(backup)
            raise
    if backup is not None:
        print("Прежняя конфигурация сохранена:", backup)
    else:
        print("Прежней конфигурации нет; резервная копия не требуется.")
    if services:
        result = subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
        if result.returncode:
            print("Файлы служб установлены. Выполните systemctl --user daemon-reload после входа.")
    print("Конфигурация готова. Войдите в новый сеанс Hyprland.")
    print("Проверка в новом сеансе: ~/.local/bin/hyprstack-doctor и hyprctl configerrors")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Первоначальная настройка Hyprstack для текущего пользователя")
    parser.add_argument("--terminal", help="Команда установленного терминала, например foot или kitty")
    parser.add_argument("--browser", help="Команда установленного браузера, например firefox или chromium")
    parser.add_argument("--no-services", action="store_true", help="Не копировать службы (если их предоставляет системный модуль)")
    parser.add_argument("--prepare", action="store_true", help="Сохранить выбор для применения после выхода из Hyprland")
    parser.add_argument("--dry-run", action="store_true", help="Показать действия без изменения файлов")
    args = parser.parse_args(argv)
    try:
        if os.geteuid() == 0:
            raise ValueError("Запускайте настройку своим пользователем, без sudo.")
        layout = Update()
        # Empty XDG variables mean the defaults, as in the documented Bash build.
        layout.config = Path(os.environ.get("XDG_CONFIG_HOME") or layout.home / ".config")
        layout.data = Path(os.environ.get("XDG_DATA_HOME") or layout.home / ".local/share")
        layout.state = Path(os.environ.get("XDG_STATE_HOME") or layout.home / ".local/state")
        layout.root = layout.state / "hyprstack-install"
        services = not args.no_services
        validate_paths(layout, services)
        terminal = application(args.terminal, "терминал", TERMINALS)
        browser = application(args.browser, "браузер", BROWSERS)
        if services and not shutil.which("systemctl"):
            raise ValueError("Не найден systemctl. Эта инструкция рассчитана на пользовательский systemd.")
        if not shutil.which("hyprctl"):
            raise ValueError("Не найден hyprctl. Сначала установите зависимости и соберите Hyprstack.")
        print("Конфигурация:", layout.config)
        print("Терминал:", shlex.join(terminal), "· браузер:", shlex.join(browser))
        if args.dry_run:
            print("Будут установлены hypr/, hyprstack/" + (" и две пользовательские службы." if services else "."))
            print("Существующие конфиги будут сохранены в", layout.config / "hyprstack-backup.*")
            return 0
        with installation_lock(layout):
            if args.prepare or active_compositors(layout):
                prepare(layout, terminal, browser, services)
            else:
                apply_configuration(layout, terminal, browser, services)
        return 0
    except (OSError, ValueError, KeyError, EOFError, subprocess.SubprocessError) as error:
        print("configure: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
