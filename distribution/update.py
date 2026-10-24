#!/usr/bin/env python3
"""Update a user installation; keep preferences and a reversible backup."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from update_transaction import Installer, read_json

ROOT = Path(__file__).resolve().parents[1]


def capture(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


class Update(Installer):
    staging: Path | None = None

    def plan(self):
        if self.staging is None:
            raise ValueError("No staged build")
        yield from self.tree(self.staging / "bin", self.bin)
        yield from self.tree(self.staging / "share", self.data)
        for file in self.tree(ROOT / "shell/assets/hyprland/config", self.config / "hypr"):
            file.preserve = file.path == self.config / "hypr/scheme/current.lua"
            yield file
        for file in self.tree(ROOT / "distribution/defaults/hyprstack", self.config / "hyprstack"):
            file.preserve = file.path.name != "hypr-user.lua"
            yield file
        for unit in ("hyprstack-session.service", "hyprstack-vpn.service"):
            yield from self.tree(ROOT / "distribution/systemd/user" / unit,
                                 self.config / "systemd/user" / unit)


def validate_destinations(update, files):
    roots = (update.config, update.data, update.state, update.bin)
    for root in (*roots, update.root):
        if not root.is_absolute() or root == Path("/"):
            raise ValueError("XDG paths must be absolute user directories: " + str(root))
    for file in files:
        if not any(file.path.is_relative_to(root) for root in roots):
            raise ValueError("Destination outside installation roots: " + str(file.path))
        parent = file.path.parent
        while parent != parent.parent:
            if parent.is_symlink():
                raise ValueError("Каталог управляется ссылкой: " + str(parent) + ". Используйте свой менеджер конфигурации или ручное обновление из INSTALL.md.")
            parent = parent.parent
        update.fingerprint(file.path)


@contextmanager
def installation_lock(update):
    update.root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (update.root / "install.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Другое обновление Hyprstack уже выполняется") from None
        yield


def active_compositors(update):
    """Ignore nested test sessions and other users' configuration directories."""
    try:
        output = capture(["hyprctl", "-j", "instances"]).strip()
        # hyprctl 0.56.2 prints a bare closing bracket for an empty instance list.
        instances = [] if output.lower() in ("", "]", "no instances", "no instances found") else json.loads(output)
    except ValueError:
        raise ValueError("Не удалось проверить запущенные сеансы Hyprland") from None
    active = []
    for instance in instances:
        try:
            proc = Path("/proc") / str(int(instance["pid"]))
            if proc.stat().st_uid != os.getuid():
                continue
            environment = dict(part.split(b"=", 1) for part in (proc / "environ").read_bytes().split(b"\0") if b"=" in part)
            home = Path(os.fsdecode(environment[b"HOME"]))
            config = Path(os.fsdecode(environment.get(b"XDG_CONFIG_HOME", os.fsencode(home / ".config"))))
            if home == update.home and config == update.config:
                active.append(instance["instance"])
        except (OSError, ValueError, KeyError, TypeError):
            continue
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if signature and capture(["hyprctl", "-i", signature, "-j", "version"]) and signature not in active:
        active.append(signature)
    return active


def require_logged_out(update):
    if active_compositors(update):
        raise ValueError("Завершите сеанс Hyprland, перейдите в TTY (Ctrl+Alt+F3) и запустите ./update.sh там. Открытые приложения автоматически не закрываются.")


def pull_sources():
    if not (ROOT / ".git").exists():
        print("Архив ZIP: используются скачанные исходники, Git пропущен.", flush=True)
        return False
    if not shutil.which("git"):
        raise ValueError("Для обновления Git-клона требуется git")
    result = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True, check=True)
    if result.stdout.strip():
        raise ValueError("В исходниках есть локальные изменения. Сохраните их коммитом или git stash; для сборки текущих файлов используйте ./update.sh --no-pull.")
    subprocess.run(["git", "pull", "--ff-only"], cwd=ROOT, check=True)
    return True


def preflight():
    missing = [name for name in ("Hyprland", "hyprctl", "qs", "cmake", "ninja", "pkg-config", "c++", "msgfmt") if not shutil.which(name)]
    if missing:
        raise ValueError("Не найдены зависимости: " + ", ".join(missing) + ". См. INSTALL.md.")
    hypr = json.loads(capture(["Hyprland", "--version-json"]) or "{}")
    if hypr.get("version") != "0.56.2" or not hypr.get("abiHash"):
        raise ValueError("Нужен Hyprland 0.56.2 с совместимыми заголовками. См. INSTALL.md.")
    subprocess.run([sys.executable, str(ROOT / "distribution/check_headers.py"), hypr["abiHash"]], check=True)
    for command, minimum, label in ((["qs", "--version"], (0, 3, 1), "Quickshell"),
            (["pkg-config", "--modversion", "Qt6Core"], (6, 9, 0), "Qt")):
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", capture(command))
        if not match or tuple(map(int, match.groups())) < minimum:
            raise ValueError(label + " не соответствует требованиям INSTALL.md")
    return hypr


def build(update, jobs, hypr):
    identity = "\n".join((str(ROOT), hypr["abiHash"], capture(["pkg-config", "--modversion", "Qt6Core"]), capture(["c++", "--version"])))
    key = hashlib.sha256(identity.encode()).hexdigest()[:16]
    directory = Path(os.environ.get("XDG_CACHE_HOME", str(update.home / ".cache"))) / "hyprstack-build" / key
    subprocess.run(["cmake", "-S", str(ROOT), "-B", str(directory), "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=" + str(update.home / ".local"),
        "-DCMAKE_INSTALL_BINDIR=bin", "-DCMAKE_INSTALL_DATADIR=share", "-DHYPRSTACK_AUDIO_VISUALIZER=OFF"], check=True)
    subprocess.run(["cmake", "--build", str(directory), "--parallel", str(jobs)], check=True)
    return directory


def rollback(update, dry_run=False):
    latest = read_json(update.pending) or read_json(update.latest)
    if not latest:
        raise ValueError("Нет автоматической резервной копии для отката")
    directory = Path(latest["transaction"])
    if not directory.is_relative_to(update.root / "backups"):
        raise ValueError("Недопустимый путь журнала отката")
    journal = read_json(directory / "journal.json")
    if not journal or journal.get("rolled_back"):
        raise ValueError("Последнее обновление уже отменено")
    if dry_run:
        print("Откат:", directory)
    else:
        update.rollback_journal(directory)
        print("Восстановлено из:", directory)


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(description="Обновить Hyprstack с резервной копией и сохранением настроек")
    parser.add_argument("--no-pull", action="store_true", help="Собрать текущие исходники без git pull")
    parser.add_argument("--dry-run", action="store_true", help="Показать действия без сборки и изменения файлов")
    parser.add_argument("--rollback", action="store_true", help="Отменить последнее автоматическое обновление")
    parser.add_argument("--jobs", type=int, choices=range(1, 65), default=2, metavar="N", help="Параллельные задачи сборки (по умолчанию 2)")
    args = parser.parse_args(arguments)
    update = Update()
    try:
        if os.geteuid() == 0:
            raise ValueError("Запускайте ./update.sh обычным пользователем, без sudo")
        if Path("/etc/NIXOS").exists() or os.environ.get("HYPRSTACK_DATA_DIR", "").startswith("/nix/store/"):
            raise ValueError("На NixOS обновляйте вход hyprstack и пересобирайте свою конфигурацию. См. MAINTENANCE.md.")
        if args.dry_run:
            if args.rollback:
                rollback(update, True)
            else:
                print("План: git pull --ff-only" if not args.no_pull and (ROOT / ".git").exists() else "План: текущие исходники")
                print("Проверка зависимостей → сборка → резервная копия → обновление файлов")
                print("Программы:", update.bin)
                print("Данные:", update.data / "hyprstack")
                print("Конфигурация:", update.config / "hypr")
                print("Личные Lua/JSON-настройки и текущая тема сохраняются.")
                print("Резервные копии:", update.root / "backups")
            return 0
        require_logged_out(update)
        with installation_lock(update):
            if not args.rollback and not args.no_pull and pull_sources():
                # Reload the updater itself if git pull brought a newer implementation.
                os.execv(sys.executable, [sys.executable, str(Path(__file__).resolve()), "--no-pull", *arguments])
            if args.rollback:
                rollback(update)
            else:
                hypr = preflight()
                directory = build(update, args.jobs, hypr)
                with tempfile.TemporaryDirectory(prefix="hyprstack-stage-") as stage:
                    subprocess.run(["cmake", "--install", str(directory)], check=True, env=dict(os.environ, DESTDIR=stage))
                    update.staging = Path(stage) / str(update.home / ".local").lstrip("/")
                    files = list(update.plan())
                    validate_destinations(update, files)
                    require_logged_out(update)
                    update.plan = lambda: iter(files)
                    update.transaction("install")
        if shutil.which("systemctl"):
            subprocess.run(["systemctl", "--user", "daemon-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("Готово. Войдите в Hyprland и выполните hyprstack-doctor.", flush=True)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Обновление остановлено:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
