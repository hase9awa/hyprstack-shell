#!/usr/bin/env python3
"""One-command desktop updates; explicit status/check/prepare actions return JSON."""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import update as deployment
from update_transaction import atomic_json, read_json

REPOSITORY = "hase9awa/hyprstack-shell"
API = "https://api.github.com/repos/" + REPOSITORY
RELEASES = "https://github.com/" + REPOSITORY + "/releases"
VERSION = re.compile(r"v?((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?")
ACTIVE_PHASES = {"checking", "downloading", "building", "starting", "waiting", "installing"}


def version(value):
    match = VERSION.fullmatch(value) if isinstance(value, str) else None
    if not match:
        raise ValueError("Unsupported version: " + str(value))
    # Remote candidates are stable releases. A prerelease of the installed
    # version sorts before its stable release, without guessing from dates.
    return (*map(int, match[1].split(".")), not bool(match[2]))


def load(path, fallback=None):
    try:
        value = read_json(path, fallback)
        return value if isinstance(value, dict) else fallback
    except (OSError, ValueError):
        return fallback


def request(url):
    return urlopen(Request(url, headers={"User-Agent": "Hyprstack-Updater",
        "Accept": "application/vnd.github+json"}), timeout=30)


def extract(archive, destination):
    """Source archives may contain only bounded regular files/directories."""
    root, total = None, 0
    with tarfile.open(archive, "r:gz") as source:
        for count, member in enumerate(source, 1):
            parts = PurePosixPath(member.name).parts
            if (not parts or member.name.startswith("/") or ".." in parts or "\\" in member.name
                    or not (member.isdir() or member.isfile())):
                raise ValueError("Unsafe path in the release archive: " + member.name)
            if root is None:
                root = parts[0]
            if parts[0] != root:
                raise ValueError("The release archive must have one source directory")
            total += member.size
            if count > 30000 or total > 512 * 1024 * 1024:
                raise ValueError("The release archive is too large")
            path = destination.joinpath(*parts)
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as stream, path.open("wb") as out:
                    shutil.copyfileobj(stream, out)
                path.chmod(0o755 if member.mode & 0o111 else 0o644)
    if root is None:
        raise ValueError("The release archive is empty")
    return destination / root


class Updates:
    def __init__(self, current=None):
        self.installation = deployment.Update()
        self.data = Path(os.environ.get("HYPRSTACK_DATA_DIR", str(self.installation.data / "hyprstack")))
        metadata = load(self.data / "version.json", {})
        if not isinstance(metadata, dict):
            metadata = {}
        self.current = current or metadata.get("version", "")
        if not self.current:
            # Installations predating the updater have no version.json yet.
            match = re.search(r"\bhyprstack\s+(\d+\.\d+\.\d+)", deployment.capture(["hyprstack", "--version"]))
            self.current = match[1] if match else ""
        self.progress = None
        self.state = self.installation.state / "hyprstack/updates"
        self.cache = Path(os.environ.get("XDG_CACHE_HOME", str(self.installation.home / ".cache"))) / "hyprstack-updates"
        self.status_file = self.state / "status.json"
        self.ready_file = self.state / "ready.json"
        self.stage = self.cache / "ready"
        self.log = self.state / "update.log"

    def capabilities(self):
        if Path("/etc/NIXOS").exists() or str(self.data.resolve()).startswith("/nix/store/"):
            reason = "nix"
        elif self.data.resolve() != (self.installation.data / "hyprstack").absolute():
            reason = "system"
        elif not all(shutil.which(command) for command in ("systemctl", "systemd-run")):
            reason = "systemd"
        else:
            reason = ""
        return {"can_install": not reason, "install_reason": reason}

    def status(self):
        saved = load(self.status_file, {})
        result = dict(saved if isinstance(saved, dict) else {}, current_version=self.current,
            log_path=str(self.log), log_exists=self.log.is_file(), **self.capabilities())
        if not isinstance(result.get("phase"), str):
            result["phase"] = "idle"
        try:
            result["available"] = bool(result.get("latest_version") and version(result["latest_version"]) > version(self.current))
        except ValueError:
            result["available"] = False
        prepared = load(self.ready_file, {})
        result["ready"] = bool(isinstance(prepared, dict) and prepared.get("stage") == str(self.stage)
            and self.stage.is_dir() and prepared.get("version") == result.get("latest_version") and result["available"])
        if result["phase"] in ACTIVE_PHASES:
            pid = result.get("pid")
            alive = True
            if pid:
                try:
                    os.kill(int(pid), 0)
                except (OSError, ValueError):
                    alive = False
            elif time.time() - result.get("updated_at", 0) > 30:
                alive = False
            if not alive:
                result.update(phase="ready" if result["ready"] else "error", error="The previous update was interrupted")
        return result

    def save(self, **fields):
        state = self.status()
        if self.progress and fields.get("phase") != state.get("phase"):
            messages = {"checking": "Проверка обновлений…", "downloading": "Загрузка исходников релиза…",
                "building": "Сборка обновления. Это может занять несколько минут.",
                "ready": "Обновление подготовлено.", "installing": "Установка с резервной копией…"}
            if fields.get("phase") in messages:
                self.progress(messages[fields["phase"]])
        state.update(fields, updated_at=time.time())
        atomic_json(self.status_file, state)
        return state

    def require_installable(self):
        if os.geteuid() == 0:
            raise ValueError("Run the updater as your desktop user, without sudo")
        reason = self.capabilities()["install_reason"]
        if reason:
            raise ValueError("This installation must be updated with its configuration/package manager: " + reason)

    def check(self):
        version(self.current)
        self.save(phase="checking", pid=os.getpid(), error="")
        try:
            with request(API + "/releases/latest") as response:
                raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise ValueError("The release response is too large")
            release = json.loads(raw)
        except HTTPError as error:
            if error.code != 404:
                raise
            error.close()
            return self.save(phase="idle", pid=None, latest_version="", available=False,
                checked_at=time.time(), no_releases=True)
        if not isinstance(release, dict) or release.get("draft") or release.get("prerelease"):
            raise ValueError("GitHub did not return a stable release")
        tag = release.get("tag_name", "")
        if not isinstance(tag, str) or not VERSION.fullmatch(tag) or VERSION.fullmatch(tag)[2]:
            raise ValueError("The latest release has an unsupported version tag")
        latest = VERSION.fullmatch(tag)[1]
        available = version(latest) > version(self.current)
        prepared = load(self.ready_file, {})
        if not isinstance(prepared, dict):
            prepared = {}
        return self.save(phase="ready" if prepared.get("version") == latest and self.stage.is_dir() else "idle",
            pid=None, latest_version=latest, tag=tag, available=available,
            release_url=RELEASES + "/tag/" + tag, notes=str(release.get("body") or "")[:16000],
            checked_at=time.time(), no_releases=False)

    def context(self):
        return [str(path) for path in (self.installation.home, self.installation.config,
            self.installation.data, self.installation.state, self.installation.bin)]

    @staticmethod
    def digest(files):
        return hashlib.sha256("\n".join(str(file.path) + "\0" + deployment.Update.desired(file)
            for file in files).encode()).hexdigest()

    def prepare(self, jobs, release=None):
        self.require_installable()
        release = release or self.check()
        if not release["available"]:
            return
        self.cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.save(phase="downloading", pid=os.getpid(), error="")
        with self.log.open("w") as log, tempfile.TemporaryDirectory(dir=self.cache, prefix="download-") as temporary:
            work = Path(temporary)
            archive = work / "source.tar.gz"
            with request(API + "/tarball/" + release["tag"]) as response, archive.open("wb") as out:
                total, deadline = 0, time.monotonic() + 300
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > 256 * 1024 * 1024 or time.monotonic() > deadline:
                        raise ValueError("The source download exceeded its size/time limit")
                    out.write(block)
            source = extract(archive, work / "source")
            project = (source / "CMakeLists.txt").read_text()
            match = re.search(r"\bproject\s*\(\s*hyprstack\s+VERSION\s+(\d+\.\d+\.\d+)", project)
            if not match or match[1] != release["latest_version"]:
                raise ValueError("The source version does not match the selected release")
            for required in ("distribution/update.py", "shell/shell.qml", "third_party/m3shapes/CMakeLists.txt"):
                if not (source / required).is_file():
                    raise ValueError("The release source is incomplete: " + required)
            checkout = self.cache / "source"
            if checkout.exists():
                shutil.rmtree(checkout)
            source.rename(checkout)
            deployment.ROOT = checkout
            self.save(phase="building", pid=os.getpid())
            hypr = deployment.preflight(log)
            build = deployment.build(self.installation, jobs, hypr, log)
            subprocess.run(["cmake", "--install", str(build)], check=True,
                env=dict(os.environ, DESTDIR=str(work / "install")), stdout=log, stderr=subprocess.STDOUT)
            staged = work / "install" / str(self.installation.home / ".local").lstrip("/")
            self.installation.staging = staged
            files = list(self.installation.plan())
            deployment.validate_destinations(self.installation, files)
            digest = self.digest(files)
            if self.stage.exists():
                shutil.rmtree(self.stage)
            staged.rename(self.stage)
            atomic_json(self.ready_file, {"stage": str(self.stage), "version": release["latest_version"],
                "context": self.context(), "digest": digest, "abi": hypr["abiHash"],
                "qt": deployment.capture(["pkg-config", "--modversion", "Qt6Core"])})
        self.save(phase="ready", pid=None, error="")

    def prepared(self):
        ready = load(self.ready_file)
        if (not isinstance(ready, dict) or ready.get("stage") != str(self.stage)
                or ready.get("context") != self.context() or not self.stage.is_dir()):
            raise ValueError("Prepare the update again: its staged files are missing or belong to another installation")
        if version(ready.get("version", "")) <= version(self.current):
            raise ValueError("The prepared version is already installed or older than this installation")
        self.installation.staging = self.stage
        files = list(self.installation.plan())
        deployment.validate_destinations(self.installation, files)
        if self.digest(files) != ready.get("digest"):
            raise ValueError("The staged files have changed. Prepare the update again")
        hypr = json.loads(deployment.capture(["Hyprland", "--version-json"]) or "{}")
        if (hypr.get("abiHash") != ready.get("abi")
                or deployment.capture(["pkg-config", "--modversion", "Qt6Core"]) != ready.get("qt")):
            raise ValueError("Hyprland or Qt changed after the build. Prepare the update again")
        return ready, files

    def start_install(self):
        self.require_installable()
        with deployment.installation_lock(self.installation):
            self.prepared()
            self.save(phase="starting", pid=None, error="")
        command = ["systemd-run", "--user", "--quiet", "--collect", "--unit=hyprstack-update",
            "--service-type=exec", "--property=TimeoutStopSec=120"]
        # A transient user service survives the graphical session and shell.
        # Pass the desktop's actual paths rather than stale manager defaults.
        environment = {"HOME": str(self.installation.home), "PATH": os.environ.get("PATH", os.defpath),
            "XDG_CONFIG_HOME": str(self.installation.config), "XDG_DATA_HOME": str(self.installation.data),
            "XDG_STATE_HOME": str(self.installation.state), "XDG_CACHE_HOME": str(self.cache.parent),
            "HYPRSTACK_DATA_DIR": str(self.data),
            "HYPRLAND_INSTANCE_SIGNATURE": os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")}
        if os.environ.get("XDG_RUNTIME_DIR"):
            environment["XDG_RUNTIME_DIR"] = os.environ["XDG_RUNTIME_DIR"]
        for name, value in environment.items():
            command.append("--setenv=" + name + "=" + value)
        command.extend(["--setenv=PYTHONDONTWRITEBYTECODE=1", "--", sys.executable,
            str(Path(__file__).resolve()), "--current-version", self.current, "_apply"])
        subprocess.run(command, check=True, capture_output=True, text=True, timeout=20)

    def apply(self, logout=True):
        self.require_installable()
        ready, files = self.prepared()
        signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if logout and not re.fullmatch(r"[A-Za-z0-9_.-]+", signature):
            raise ValueError("Install the update from the Hyprland desktop session")
        # Fail before logging out if hyprctl cannot reliably inspect sessions.
        subprocess.run(["hyprctl", "-j", "instances"], check=True, capture_output=True, timeout=10)
        active = deployment.active_compositors(self.installation)
        if not logout and active:
            raise ValueError("Hyprland is still running; no installed files were changed")
        if any(instance != signature for instance in active):
            raise ValueError("Close the other Hyprland sessions before installing the update")
        self.save(phase="waiting", pid=os.getpid(), error="")
        if signature in active:
            subprocess.run(["hyprctl", "-i", signature, "dispatch", "exit"],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        deadline = time.monotonic() + 60
        while deployment.active_compositors(self.installation):
            if time.monotonic() > deadline:
                raise ValueError("Hyprland has not exited; no installed files were changed")
            time.sleep(.25)
        deployment.require_logged_out(self.installation)
        deployment.validate_destinations(self.installation, files)
        self.save(phase="installing", pid=os.getpid())
        self.installation.plan = lambda: iter(files)
        with self.log.open("a") as log, redirect_stdout(log):
            self.installation.transaction("install")
        self.ready_file.unlink(missing_ok=True)
        self.current = ready["version"]
        self.save(phase="done", pid=None, error="")
        shutil.rmtree(self.stage, ignore_errors=True)
        try:
            subprocess.run(["systemctl", "--user", "daemon-reload"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        except (OSError, subprocess.SubprocessError):
            pass


def confirm_logout():
    try:
        with open("/dev/tty", "r+") as terminal:
            terminal.write("\nСохраните работу и закройте приложения. Установка завершит сеанс Hyprland.\n"
                "Установить обновление и выйти? [д/Н]: ")
            terminal.flush()
            return terminal.readline().strip().lower() in ("д", "да", "y", "yes")
    except OSError:
        raise ValueError("Для подтверждения выхода нужен терминал. Для заранее согласованного обновления используйте --yes.") from None


def update_command(manager, jobs, yes=False):
    manager.require_installable()
    manager.progress = lambda message: print(message, flush=True)
    print("Установленная версия Hyprstack: " + (manager.current or "не определена"), flush=True)
    with deployment.installation_lock(manager.installation):
        release = manager.check()
        if not release["available"]:
            print("Опубликованных релизов пока нет." if release.get("no_releases") else "Установлена актуальная версия.", flush=True)
            return 0
        print("Доступна версия " + release["latest_version"] + ". Журнал: " + str(manager.log), flush=True)
        reuse = False
        if manager.status()["ready"]:
            try:
                manager.prepared()
                reuse = True
            except (OSError, ValueError):
                pass
        if not reuse:
            manager.prepare(jobs, release)
        # A failed inspection must never be mistaken for a logged-out desktop.
        subprocess.run(["hyprctl", "-j", "instances"], check=True, capture_output=True, timeout=10)
        active = deployment.active_compositors(manager.installation)
        if not active:
            manager.apply(logout=False)
            print("Готово. Обновление установлено; можно войти в Hyprland.", flush=True)
            return 0
        signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if active != [signature]:
            raise ValueError("Запустите обновление в своём сеансе Hyprland и завершите другие сеансы этой установки.")
    if not yes and not confirm_logout():
        print("Выход отменён. Сборка сохранена; для установки снова запустите hyprstack-update.", flush=True)
        return 0
    print("Установка продолжится в отдельной службе после выхода.\n"
        "Дождитесь её завершения перед входом: hyprstack-update status", flush=True)
    manager.start_install()
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current-version", help="Running shell version (otherwise read the installed metadata)")
    parser.add_argument("--jobs", type=int, choices=range(1, 65), default=2, metavar="N")
    parser.add_argument("--yes", "-y", action="store_true", help="Заранее подтвердить выход из Hyprland после подготовки")
    parser.add_argument("action", nargs="?", default="update", choices=("update", "rollback", "status", "check", "prepare", "install", "_apply"),
        help="Без аргументов: проверить, подготовить и установить обновление")
    args = parser.parse_args(argv)
    manager = Updates(args.current_version)
    try:
        if args.action == "update":
            return update_command(manager, args.jobs, args.yes)
        elif args.action == "rollback":
            manager.require_installable()
            with deployment.installation_lock(manager.installation):
                deployment.require_logged_out(manager.installation)
                deployment.rollback(manager.installation)
                manager.current = Updates().current
                manager.save(phase="idle", pid=None, error="")
            print("Откат выполнен. Можно войти в Hyprland.", flush=True)
            return 0
        elif args.action == "install":
            manager.start_install()
        elif args.action != "status":
            with deployment.installation_lock(manager.installation):
                if args.action == "check":
                    manager.check()
                elif args.action == "prepare":
                    manager.prepare(args.jobs)
                else:
                    manager.apply()
        print(json.dumps(manager.status(), ensure_ascii=False))
        return 0
    except (OSError, ValueError, URLError, tarfile.TarError, subprocess.SubprocessError) as error:
        # Keep a successful release check and a prepared build after failures.
        detail = str(error)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            detail += ": " + str(error.stderr).strip()
        try:
            with deployment.installation_lock(manager.installation):
                manager.save(phase="error", pid=None, error=detail, error_action=args.action)
        except (OSError, ValueError):
            # An operation owned by another process must keep its status.
            pass
        if args.action in ("update", "rollback"):
            print("Обновление остановлено: " + detail, file=sys.stderr)
        else:
            result = manager.status()
            result["error"] = detail
            print(json.dumps(result, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
