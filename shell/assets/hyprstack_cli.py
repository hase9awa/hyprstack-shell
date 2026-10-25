#!/usr/bin/env python3
"""Hyprstack desktop commands. No background process is started at login."""
from __future__ import annotations

import argparse
import colorsys
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import random
import re
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import time
import unicodedata

import theme_manager as themes
from i18n import _, configure_argparse

VERSION = "1.2.1"
ASSETS = Path(__file__).resolve().parent
CONFIG = themes.CONFIG
STATE = themes.STATE
VARIANTS = ("tonalspot", "vibrant", "expressive", "fidelity", "content", "fruitsalad", "rainbow", "neutral", "monochrome")


def run(command, **kwargs):
    if not shutil.which(str(command[0])):
        raise ValueError(_("Missing command: %1").replace("%1", str(command[0])))
    return subprocess.run(list(map(str, command)), check=True, **kwargs)


def shell_path():
    return Path(os.environ.get("HYPRSTACK_SHELL_DIR", ASSETS.parent))


def ipc(*args):
    return run(["qs", "-p", shell_path(), "ipc", "call", *args], timeout=10)


def xdg_directory(kind):
    value = os.environ.get("XDG_" + kind + "_DIR")
    if not value and shutil.which("xdg-user-dir"):
        value = subprocess.check_output(["xdg-user-dir", kind], text=True, timeout=5).strip()
    return Path(value or Path.home() / {"PICTURES": "Pictures", "VIDEOS": "Videos"}[kind])


def wallpaper_path():
    try:
        path = (STATE / "wallpaper/path.txt").read_text().strip()
        return Path(path) if path and Path(path).is_file() else None
    except OSError:
        return None


def image_seed(path):
    from PIL import Image, ImageOps
    with Image.open(path) as source:
        source.thumbnail((96, 96))
        image = ImageOps.exif_transpose(source)
        image = image.convert("RGB")
        quantized = image.quantize(colors=8)
        dominant = max(quantized.getcolors(), key=lambda c: c[0])[1]
        return tuple(quantized.getpalette()[dominant * 3:dominant * 3 + 3])


def dynamic_scheme(path, mode=None, variant="tonalspot"):
    if path is None:
        raise ValueError(_("Wallpaper does not exist"))
    seed = image_seed(path)
    hue, lightness, saturation = colorsys.rgb_to_hls(*(c / 255 for c in seed))
    mode = mode or ("light" if lightness > .6 else "dark")
    if mode not in themes.MODES or variant not in VARIANTS:
        raise ValueError(_("Invalid theme mode or variant"))
    saturation = 0 if variant == "monochrome" else min(.25, saturation) if variant == "neutral" else max(.45, saturation)
    if variant in ("expressive", "fruitsalad", "rainbow"):
        hue = (hue + {"expressive": .33, "fruitsalad": .15, "rainbow": .5}[variant]) % 1
    def colour(h, l, s):
        return "".join(f"{round(c * 255):02x}" for c in colorsys.hls_to_rgb(h % 1, l, s))
    colours = themes.palette({
        "background": colour(hue, .08 if mode == "dark" else .96, .12),
        "foreground": "eeeeee" if mode == "dark" else "202020",
        "accent": colour(hue, .72 if mode == "dark" else .38, saturation),
        "secondary": colour(hue + .12, .72 if mode == "dark" else .38, saturation * .7),
        "tertiary": colour(hue + .33, .72 if mode == "dark" else .38, saturation),
    }, mode)
    return {"name": "dynamic", "flavour": "default", "mode": mode, "variant": variant, "colours": colours}


def scheme_command(args):
    catalogue = themes.catalogue()["themes"]
    current = themes.read_current()
    if args.operation == "list":
        if args.variants:
            print("\n".join(VARIANTS))
        elif args.names:
            print("\n".join(t["id"] for t in catalogue) + "\ndynamic")
        elif args.flavours:
            print("\n".join(sorted({v["flavour"] for t in catalogue for v in t["variants"]})))
        elif args.modes:
            print("dark\nlight")
        elif args.accents:
            print("\n".join(sorted({v["accent"] for t in catalogue for v in t["variants"]})))
        else:
            data = {t["id"]: {v["flavour"]: v["colours"] for v in reversed(t["variants"])} for t in catalogue}
            data["dynamic"] = {"default": current.get("colours", themes.builtins()[0]["variants"][0]["colours"])}
            print(json.dumps(data))
    elif args.operation == "get":
        fields = [key for key in ("name", "flavour", "mode", "variant", "accent") if getattr(args, key)]
        if fields:
            print("\n".join(str(current.get(key, "")) for key in fields))
        else:
            print(json.dumps(current))
    else:
        identifier = args.name or current.get("name", "hyprstack-catppuccin")
        if args.random:
            identifier = random.choice(catalogue)["id"]
        mode = args.mode or current.get("mode", "dark")
        if identifier == "dynamic":
            if args.accent or args.flavour not in (None, "default"):
                raise ValueError(_("Dynamic schemes use --variant; choose a preset to use --accent"))
            themes.save_current(dynamic_scheme(wallpaper_path(), mode, args.variant or current.get("variant", "tonalspot")))
        else:
            item = next((t for t in catalogue if identifier == t["id"] or identifier in t["aliases"]), None)
            if item is None:
                raise ValueError(_("Unknown colour scheme: %1").replace("%1", identifier))
            themes.apply_theme(item["id"], mode, args.accent, args.flavour)
            if args.variant:
                themes.save_current({**themes.read_current(), "variant": args.variant})


def wallpaper_command(args):
    current = themes.read_current()
    if args.print is not None:
        print(json.dumps(dynamic_scheme(Path(args.print) if args.print else wallpaper_path(),
                                       current.get("mode", "dark") if args.no_smart else None,
                                       current.get("variant", "tonalspot"))))
        return
    path = Path(args.file).expanduser().resolve() if args.file else None
    if args.random is not None:
        directory = Path(args.random).expanduser() if args.random else Path(os.environ.get("HYPRSTACK_WALLPAPERS_DIR", xdg_directory("PICTURES") / "Wallpapers"))
        candidates = [p for p in directory.rglob("*") if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".gif")]
        if not candidates:
            raise ValueError(_("No wallpapers found in %1").replace("%1", str(directory)))
        others = [p for p in candidates if p.resolve() != wallpaper_path()]
        path = random.choice(others or candidates).resolve()
    if not path:
        print(wallpaper_path() or "")
        return
    if not path.is_file():
        raise ValueError(_("Wallpaper does not exist"))
    # Decode first so a bad file cannot replace the last working wallpaper.
    seed = image_seed(path)
    del seed
    if current.get("name") == "dynamic":
        themes.save_current(dynamic_scheme(path, current.get("mode", "dark") if args.no_smart else None,
                                           current.get("variant", "tonalspot")))
    directory = STATE / "wallpaper"
    directory.mkdir(parents=True, exist_ok=True)
    themes.atomic_json(directory / "metadata.json", {"path": str(path)})
    temporary = directory / ("path-" + str(os.getpid()) + ".tmp")
    try:
        temporary.write_text(str(path) + "\n")
        temporary.replace(directory / "path.txt")
    finally:
        temporary.unlink(missing_ok=True)


def screenshot_command(args):
    if args.region == "slurp" or args.freeze:
        ipc("picker", "openFreeze" if args.freeze else "open")
        return
    directory = Path(os.environ.get("HYPRSTACK_SCREENSHOTS_DIR", xdg_directory("PICTURES") / "Screenshots"))
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ("Screenshot-" + datetime.now().strftime("%Y-%m-%d_%H-%M-%S-%f") + ".png")
    command = ["grim"]
    if args.region:
        command += ["-g", args.region]
    elif os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], timeout=5))
        focused = next((m for m in monitors if m.get("focused")), None)
        if focused:
            command += ["-o", focused["name"]]
    run([*command, target], timeout=30)
    target.chmod(0o600)
    run(["wl-copy", "--type", "image/png"], input=target.read_bytes(), timeout=10)
    if shutil.which("notify-send"):
        run(["notify-send", "-a", "hyprstack", "-h", "string:image-path:" + str(target),
             "-h", "boolean:x-hyprstack-screenshot:true", _("Screenshot taken"), str(target)], timeout=5)
    print(target)


def clipboard_command(args):
    history = subprocess.check_output(["cliphist", "list"], timeout=10)
    selected = subprocess.run(["fuzzel", "--dmenu"], input=history, stdout=subprocess.PIPE)
    if selected.returncode != 0 or not selected.stdout.strip():
        return
    if args.delete:
        run(["cliphist", "delete"], input=selected.stdout, timeout=10)
    else:
        data = subprocess.check_output(["cliphist", "decode"], input=selected.stdout, timeout=10)
        run(["wl-copy"], input=data, timeout=10)


def emoji_command(args):
    symbols = "😀 😃 😄 😁 😆 😅 😂 🙂 🙃 😉 😊 😍 🥰 😎 🤔 😴 😭 😡 🤯 🥳 😇 🤝 👍 👎 👏 🙌 👋 💪 ❤️ 💛 💚 💙 💜 🖤 🤍 💔 🔥 ✨ ⭐ 🎉 🎊 🎁 🎂 ☕ 🍕 🍔 🍎 🌍 🌞 🌙 🌈 🌻 🐈 🐕 🦊 🐧 🐢 🎮 🎵 🎬 📷 💻 ⌨️ 📱 🔧 ⚙️ 💡 📌 ✅ ❌ ⚠️ 🚀 🏠 🚗 ✈️ 🧠 👀".split()
    rows = [s + "  " + unicodedata.name(s[0], "emoji").lower() for s in symbols]
    selection = subprocess.run(["fuzzel", "--dmenu", "--prompt", _("Emoji: ")],
                               input="\n".join(rows), text=True, stdout=subprocess.PIPE)
    if selection.returncode or not selection.stdout.strip():
        return
    value = selection.stdout.split()[0]
    run(["wl-copy"], input=value.encode(), timeout=10)
    if args.paste and shutil.which("wtype"):
        run(["wtype", value], timeout=10)


def proc_identity(pid):
    try:
        # Field 22 follows the parenthesized comm, which can contain spaces.
        stat = Path(f"/proc/{int(pid)}/stat").read_text().rsplit(")", 1)[1].split()
        if stat[0] == "Z":
            return None
        return stat[19]
    except (OSError, ValueError, IndexError):
        return None


def recording_status():
    try:
        data = json.loads((STATE / "record/status.json").read_text())
        alive = data.get("running") and proc_identity(data.get("pid")) == data.get("identity") and data.get("identity") is not None
        if alive:
            data["elapsed"] = max(0, (data.get("paused_at") or time.time()) - data["started"] - data.get("pause_duration", 0))
            data["state"] = "paused" if data.get("paused") else "recording"
            return data
    except (OSError, ValueError, KeyError, TypeError):
        pass
    try:
        pending = json.loads((STATE / "record/start.json").read_text())
        if pending.get("identity") is not None and proc_identity(pending.get("pid")) == pending["identity"]:
            return {**pending, "running": False, "paused": False, "elapsed": 0}
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return {"running": False, "paused": False, "elapsed": 0, "state": "idle"}


def recording_output(geometry=None):
    monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], text=True, timeout=5))
    outputs = [monitor for monitor in monitors if isinstance(monitor, dict) and
               isinstance(monitor.get("name"), str) and monitor["name"] and not monitor.get("disabled")]
    if not outputs:
        raise ValueError(_("No monitor is available for recording"))
    focused = next((monitor for monitor in outputs if monitor.get("focused")), outputs[0])
    if geometry is None:
        return focused["name"]
    match = re.fullmatch(r"(-?\d+),(-?\d+)\s+(\d+)x(\d+)", geometry)
    if not match:
        raise ValueError(_("Invalid recording region"))
    x, y, width, height = map(int, match.groups())
    if width <= 0 or height <= 0:
        raise ValueError(_("Invalid recording region"))
    def overlap(monitor):
        mw, mh = monitor["width"], monitor["height"]
        if monitor.get("transform", 0) % 2:
            mw, mh = mh, mw
        scale = max(float(monitor.get("scale", 1)), .01)
        left, top = monitor.get("x", 0), monitor.get("y", 0)
        return max(0, min(x + width, left + mw / scale) - max(x, left)) * \
               max(0, min(y + height, top + mh / scale) - max(y, top))
    selected = max(outputs, key=lambda monitor: (overlap(monitor), monitor is focused))
    if not overlap(selected):
        raise ValueError(_("The recording region is outside the available monitors"))
    return selected["name"]


class RecordingCancelled(Exception):
    pass


def stop_owned_process(process, timeout=2):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def start_recording(args):
    if not shutil.which("wf-recorder"):
        raise ValueError(_("Install wf-recorder to record your screen"))
    state_dir = STATE / "record"
    state_dir.mkdir(parents=True, exist_ok=True)
    with (state_dir / "start.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        # Another launcher may have completed after our initial status query.
        if recording_status()["running"]:
            return
        selector, worker, ready = None, None, False
        pending = state_dir / "start.json"
        deferred_cancel = False
        def cancel(signum, frame):
            raise RecordingCancelled()
        def defer_cancel(signum, frame):
            nonlocal deferred_cancel
            deferred_cancel = True
        previous = {sig: signal.signal(sig, cancel) for sig in (signal.SIGTERM, signal.SIGINT)}
        try:
            state = {"pid": os.getpid(), "identity": proc_identity(os.getpid()),
                     "state": "selecting" if args.region == "slurp" else "starting"}
            themes.atomic_json(pending, state)
            geometry = args.region
            if geometry == "slurp":
                # Keep the child handle so both Escape and SIGTERM can cancel
                # the selector without leaving a layer-shell surface behind.
                # Keep selector signals unblocked while deferring parent
                # cancellation until its child handle has been assigned.
                for sig in previous:
                    signal.signal(sig, defer_cancel)
                try:
                    selector = subprocess.Popen(["slurp"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                finally:
                    for sig in previous:
                        signal.signal(sig, cancel)
                if deferred_cancel:
                    raise RecordingCancelled()
                geometry, error = selector.communicate(timeout=120)
                if selector.returncode:
                    return
                geometry = geometry.strip()
                if not geometry:
                    return
            output = recording_output(geometry)
            directory = Path(os.environ.get("HYPRSTACK_RECORDINGS_DIR", xdg_directory("VIDEOS") / "Recordings"))
            directory.mkdir(parents=True, exist_ok=True)
            target = directory / ("recording_" + datetime.now().strftime("%Y-%m-%d_%H-%M-%S-%f") + ".mp4")
            command = ["wf-recorder", "-o", output, "-f", str(target)]
            if args.sound:
                command.append("--audio")
            if geometry:
                command += ["-g", geometry]
            themes.atomic_json(pending, {**state, "state": "starting"})
            # Defer cancellation across Popen and handle assignment. Otherwise
            # a signal at that boundary could detach an unowned worker.
            mask = signal.pthread_sigmask(signal.SIG_BLOCK, previous)
            try:
                worker = subprocess.Popen([sys.executable, __file__, "--record-worker", *command], start_new_session=True,
                                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, mask)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if recording_status()["running"]:
                    ready = True
                    print(target)
                    return
                if worker.poll() is not None:
                    break
                time.sleep(.05)
            raise ValueError(_("Recorder could not start; see %1").replace("%1", str(state_dir / "recorder.log")))
        except RecordingCancelled:
            return
        finally:
            for sig in previous:
                signal.signal(sig, signal.SIG_IGN)
            stop_owned_process(selector)
            if not ready:
                stop_owned_process(worker, timeout=13)
            pending.unlink(missing_ok=True)
            for sig, handler in previous.items():
                signal.signal(sig, handler)


def record_worker(command):
    os.umask(0o077)
    directory = STATE / "record"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "worker.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 1
        path = directory / "status.json"
        with (directory / "recorder.log").open("w") as log:
            process, event = None, None
            readfd, writefd = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
            previous_fd = signal.set_wakeup_fd(writefd)
            previous = {sig: signal.signal(sig, lambda signum, frame: None)
                        for sig in (signal.SIGCHLD, signal.SIGTERM, signal.SIGINT)}
            # The launcher defers cancellation across fork/exec. Restore these
            # signals after installing our handlers, before spawning recorder.
            signal.pthread_sigmask(signal.SIG_UNBLOCK, (signal.SIGTERM, signal.SIGINT))
            try:
                signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
                runtime = os.environ.get("XDG_RUNTIME_DIR", "")
                if signature and runtime:
                    if not re.fullmatch(r"[A-Za-z0-9_.-]+", signature):
                        raise ValueError(_("Invalid Hyprland session signature"))
                    event = socket.socket(socket.AF_UNIX)
                    event.connect(str(Path(runtime) / "hypr" / signature / ".socket2.sock"))
                process = subprocess.Popen(command, stdout=log, stderr=log)
                try:
                    return process.wait(timeout=.15)
                except subprocess.TimeoutExpired:
                    pass
                data = {"running": True, "paused": False, "pid": process.pid, "identity": proc_identity(process.pid),
                        "started": time.time(), "pause_duration": 0, "path": command[command.index("-f") + 1]}
                themes.atomic_json(path, data)
                with selectors.DefaultSelector() as selector:
                    selector.register(readfd, selectors.EVENT_READ)
                    if event:
                        selector.register(event, selectors.EVENT_READ)
                    done = False
                    while not done and process.poll() is None:
                        for key, _ in selector.select():
                            if key.fileobj is event:
                                done = done or not event.recv(65536)
                            else:
                                pending = os.read(readfd, 4096)
                                done = done or signal.SIGTERM in pending or signal.SIGINT in pending
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                print(str(error), file=log, flush=True)
                return 1
            finally:
                if process and process.poll() is None:
                    # A paused recorder cannot observe a closed Wayland socket.
                    process.send_signal(signal.SIGCONT)
                    process.send_signal(signal.SIGINT)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.terminate()
                        try:
                            process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            process.kill(); process.wait()
                if event:
                    event.close()
                signal.set_wakeup_fd(previous_fd)
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
                os.close(readfd); os.close(writefd)
                themes.atomic_json(path, {"running": False, "paused": False, "elapsed": 0,
                                        "path": command[command.index("-f") + 1]})
        return process.returncode


def signal_recording(data, sig):
    # Pin the kernel process identity before checking its start time. A stale
    # state file must never signal an unrelated process which reused the PID.
    if hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal"):
        fd = os.pidfd_open(data["pid"])
        try:
            if proc_identity(data["pid"]) != data["identity"]:
                raise ValueError(_("Recording process has already stopped"))
            signal.pidfd_send_signal(fd, sig)
        finally:
            os.close(fd)
    elif proc_identity(data["pid"]) == data["identity"]:
        os.kill(data["pid"], sig)


def record_command(args):
    data = recording_status()
    if args.status:
        print(json.dumps(data))
        return
    if data.get("state") in ("selecting", "starting"):
        if args.stop:
            signal_recording(data, signal.SIGTERM)
            deadline = time.monotonic() + 15
            while proc_identity(data["pid"]) == data["identity"] and time.monotonic() < deadline:
                time.sleep(.05)
            if proc_identity(data["pid"]) == data["identity"]:
                raise ValueError(_("The recording selection could not be cancelled"))
        return
    if data["running"]:
        if args.pause:
            signal_recording(data, signal.SIGCONT if data["paused"] else signal.SIGSTOP)
            if data["paused"]:
                data["pause_duration"] += time.time() - data.pop("paused_at")
            else:
                data["paused_at"] = time.time()
            data["paused"] = not data["paused"]
            themes.atomic_json(STATE / "record/status.json", data)
        else:
            if data["paused"]:
                signal_recording(data, signal.SIGCONT)
            signal_recording(data, signal.SIGINT)
            if args.stop:
                deadline = time.monotonic() + 12
                while recording_status()["running"] and time.monotonic() < deadline:
                    time.sleep(.05)
                if recording_status()["running"]:
                    raise ValueError(_("The recording could not be stopped"))
        return
    if args.pause or args.stop:
        return
    start_recording(args)


def parser():
    configure_argparse()
    p = argparse.ArgumentParser(description=_("Control the Hyprstack desktop"), prog="hyprstack")
    p.add_argument("-v", "--version", action="version", version="hyprstack " + VERSION)
    sub = p.add_subparsers(dest="command", required=True, title=_("Commands"))
    scheme = sub.add_parser("scheme", help=_("View and change colour schemes")).add_subparsers(dest="operation", required=True)
    listing = scheme.add_parser("list")
    for flag, name in (("n", "names"), ("f", "flavours"), ("m", "modes"), ("v", "variants"), ("a", "accents")):
        listing.add_argument("-" + flag, "--" + name, action="store_true")
    get = scheme.add_parser("get")
    for flag, name in (("n", "name"), ("f", "flavour"), ("m", "mode"), ("v", "variant"), ("a", "accent")):
        get.add_argument("-" + flag, "--" + name, action="store_true")
    set_ = scheme.add_parser("set")
    set_.add_argument("-n", "--name")
    set_.add_argument("-f", "--flavour")
    set_.add_argument("-a", "--accent")
    set_.add_argument("-m", "--mode", choices=themes.MODES)
    set_.add_argument("-v", "--variant", choices=VARIANTS)
    set_.add_argument("-r", "--random", action="store_true")
    set_.add_argument("--notify", action="store_true")
    wall = sub.add_parser("wallpaper", help=_("View and change wallpapers"))
    choice = wall.add_mutually_exclusive_group()
    choice.add_argument("-p", "--print", nargs="?", const="")
    choice.add_argument("-f", "--file")
    choice.add_argument("-r", "--random", nargs="?", const="")
    wall.add_argument("-N", "--no-smart", action="store_true")
    shot = sub.add_parser("screenshot", help=_("Take a screenshot"))
    shot.add_argument("-r", "--region", nargs="?", const="slurp")
    shot.add_argument("-f", "--freeze", action="store_true")
    record = sub.add_parser("record", help=_("Record the screen"))
    record.add_argument("-r", "--region", nargs="?", const="slurp")
    record.add_argument("-s", "--sound", action="store_true")
    record.add_argument("-p", "--pause", action="store_true")
    record.add_argument("--status", action="store_true")
    record.add_argument("--stop", action="store_true")
    clip = sub.add_parser("clipboard", help=_("Open clipboard history"))
    clip.add_argument("-d", "--delete", action="store_true")
    emoji = sub.add_parser("emoji", help=_("Open emoji picker"))
    emoji.add_argument("-p", "--paste", action="store_true")
    shell = sub.add_parser("shell", help=_("Manage the shell"))
    shell.add_argument("-d", "--daemon", action="store_true")
    shell.add_argument("-k", "--kill", action="store_true")
    shell.add_argument("-r", "--restart", action="store_true")
    shell.add_argument("message", nargs="*")
    sub.add_parser("doctor", help=_("Check the installation"))
    return p


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--record-worker":
        return record_worker(sys.argv[2:])
    args = parser().parse_args()
    try:
        if args.command == "scheme": scheme_command(args)
        elif args.command == "wallpaper": wallpaper_command(args)
        elif args.command == "screenshot": screenshot_command(args)
        elif args.command == "record": record_command(args)
        elif args.command == "clipboard": clipboard_command(args)
        elif args.command == "emoji": emoji_command(args)
        elif args.command == "doctor":
            return run(["hyprstack-doctor"]).returncode
        elif args.message:
            return ipc(*args.message).returncode
        else:
            if args.kill or args.restart:
                run(["qs", "-p", shell_path(), "kill"], timeout=10)
            if not args.kill:
                command = ["hyprstack-shell"] + (["--daemonize"] if args.daemon else [])
                os.execvp(command[0], command)
        return 0
    except (OSError, ValueError, KeyError, TypeError, ImportError, subprocess.SubprocessError) as error:
        print("hyprstack: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
