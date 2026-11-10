#!/usr/bin/env python3
"""Exercise real file-dialog input on an isolated Hyprland display and bus.

Uses the same HYPRSTACK_TEST_PREFIX, _QS, _WTYPE and _POINTER as
test_screenshots.py. No pointer/keyboard events reach the user's session.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1] / "shell"


def main():
    if "--private-bus" not in sys.argv:
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--private-bus"], check=True)
        return
    prefix = Path(os.environ["HYPRSTACK_TEST_PREFIX"])
    pointer = os.environ["HYPRSTACK_TEST_POINTER"]
    wtype = os.environ["HYPRSTACK_TEST_WTYPE"]
    qs = os.environ["HYPRSTACK_TEST_QS"]
    parent = dict(os.environ)
    base = Path(tempfile.mkdtemp(prefix="hs-files-"))
    print("Artifacts:", base, flush=True)
    runtime, home = base / "r", base / "home"
    runtime.mkdir(mode=0o700)
    home.mkdir()
    for name in ["Files with spaces", "Каталог", ".hidden folder"]:
        (home / name).mkdir()
    for name in ["first.txt", "second.txt", ".hidden.txt", "hash # %.txt"]:
        (home / name).write_text("test contents")
    # A valid image with URI-sensitive characters exercises URL encoding.
    from PIL import Image
    Image.new("RGB", (32, 32), "#83a598").save(home / "image # %.png")
    for index, name in enumerate(["first.txt", "hash # %.txt", "second.txt", "image # %.png"]):
        os.utime(home / name, (1600000000 + index * 100, 1600000000 + index * 100))
    config = base / "config"
    prefs = config / "hyprstack"
    prefs.mkdir(parents=True)
    shutil.copytree(SOURCE / "assets/hyprland/config", config / "hypr")
    (prefs / "hypr-user.lua").write_text(
        'dofile(' + json.dumps(str(SOURCE / "assets/hyprland/layouts.lua")) + ')\n'
        'hl.monitor({output="",mode="1280x800@60",position="0x0",scale=1})\n'
        'hl.config({input={follow_mouse=0,resolve_binds_by_sym=true},cursor={no_warps=true}})\n')
    (prefs / "tiling.json").write_text('{"focusOnHover":false,"edgeScroll":false}\n')
    shell = base / "shell"
    shell.mkdir()
    for name in ["services", "components", "modules", "assets", "utils"]:
        (shell / name).symlink_to(SOURCE / name)
    (shell / "shell.qml").symlink_to(HERE / "filedialog_shell.qml")
    entry = base / "hyprland.lua"
    entry.write_text('local on=hl.on; hl.on=function(name,callback) '
        'if name~="hyprland.start" then return on(name,callback) end end\n'
        'dofile(' + json.dumps(str(config / "hypr/hyprland.lua")) + ')\nhl.on=on\n')
    display = Path(parent["WAYLAND_DISPLAY"])
    if not display.is_absolute(): display = Path(parent["XDG_RUNTIME_DIR"]) / display
    env = dict(parent, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
        XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(base / "data"),
        XDG_CACHE_HOME=str(base / "cache"), XDG_STATE_HOME=str(base / "state"),
        HYPRSTACK_TITLEBAR_PLUGIN=str(prefix / "share/hyprstack/native/hyprstack-bars.so"),
        HYPRSTACK_LIB_DIR=str(prefix / "share/hyprstack/lib"),
        HYPRSTACK_DATA_DIR=str(prefix / "share/hyprstack"),
        QML_IMPORT_PATH=str(prefix / "share/hyprstack/qml"),
        QML2_IMPORT_PATH=str(prefix / "share/hyprstack/qml"),
        WAYLAND_DISPLAY=str(display), AQ_DRM_DEVICES="/dev/null", HYPRSTACK_NESTED="1",
        QT_QPA_PLATFORM="wayland", DBUS_SYSTEM_BUS_ADDRESS=parent["DBUS_SESSION_BUS_ADDRESS"])
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    children = []

    def launch(command, name):
        with (base / (name + ".log")).open("w") as log:
            proc = subprocess.Popen(command, env=env, stdout=log, stderr=log, start_new_session=True)
        children.append(proc)
        return proc

    def run(command):
        return subprocess.check_output(command, env=env, text=True, timeout=10).strip()

    def wait(check, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            value = check()
            if value: return value
            time.sleep(.08)
        raise AssertionError("Timed out: " + label)

    def ipc(method, *args):
        return run([qs, "ipc", "-p", str(shell), "call", "--", "fileDialogTest", method, *map(str, args)])
    def status(): return json.loads(ipc("status"))
    def ctl(*args): return run(["hyprctl", *args])
    def key(*args): run([wtype, *args])
    def snapshot(name):
        # Optional review artifact; a compositor frame may still be pending.
        for attempt in range(3):
            try:
                run(["grim", str(base / name)])
                return
            except subprocess.SubprocessError:
                time.sleep(.15)
    def click(name):
        time.sleep(.4)
        pos = wait(lambda: json.loads(ipc("rect", name)), name)
        layers = [layer for monitor in json.loads(ctl("-j", "layers")).values()
            for level in monitor["levels"].values() for layer in level]
        layer = next(layer for layer in layers if layer["namespace"] == "hyprstack-filechooser")
        monitor = json.loads(ctl("-j", "monitors"))[0]
        with (base / "clicks.jsonl").open("a") as log:
            log.write(json.dumps({"name": name, "position": pos}) + "\n")
        run([pointer, str(round(pos["x"] + layer["x"])), str(round(pos["y"] + layer["y"])),
            str(monitor["width"]), str(monitor["height"])])
    def start(mode, path=home, multiple=False):
        ipc("start", mode, path, "true" if multiple else "false")
        wait(lambda: status()["open"] and status()["entries"], "file dialog")
        time.sleep(.4)
    def path(value):
        key("-M", "ctrl", "-k", "l", "-m", "ctrl", str(value), "-k", "Return")
    def cancel():
        key("-k", "Escape")
        wait(lambda: not status()["open"], "cancel")

    focused = json.loads(subprocess.check_output(["hyprctl", "-j", "activewindow"], text=True))
    try:
        launch(["Hyprland", "-c", str(entry)], "compositor")
        sock = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        subprocess.run(["dbus-update-activation-environment", *[k for k in env
            if k.startswith("XDG_") or k in ["HOME", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
                "DBUS_SYSTEM_BUS_ADDRESS"]]], env=env, check=True)
        shell_proc = launch([qs, "--path", str(shell), "--no-duplicate", "--no-color"], "shell")
        wait(lambda: "File dialog test underlay" in ctl("-j", "clients"), "shell")
        start(0)
        snapshot("filechooser.png")
        assert ".hidden.txt" not in status()["entries"]
        path("Files with spaces")
        wait(lambda: status()["path"] == str(home / "Files with spaces"), "relative path")
        click("fileDialogBack")
        wait(lambda: status()["path"] == str(home), "back")
        click("fileDialogForward")
        wait(lambda: status()["path"] == str(home / "Files with spaces"), "forward")
        click("fileDialogUp")
        wait(lambda: status()["path"] == str(home), "parent")
        path(home / "Каталог")
        wait(lambda: status()["path"] == str(home / "Каталог"), "Unicode path")
        path("/")
        wait(lambda: status()["path"] == "/", "filesystem root")
        path("~")
        wait(lambda: status()["path"] == str(home), "home")
        path(home / "missing")
        wait(lambda: status()["error"], "invalid path error")
        assert status()["path"] == str(home)
        print("PASS: editable paths, Unicode, relative paths, root, back/forward/up and invalid paths", flush=True)
        key("-M", "ctrl", "-k", "h", "-m", "ctrl")
        wait(lambda: ".hidden.txt" in status()["entries"], "hidden files")
        path((home / "hash # %.txt").as_uri())
        wait(lambda: status()["selected"] == [str(home / "hash # %.txt")], "encoded file URI")
        click("fileDialogAccept")
        wait(lambda: not status()["open"], "open accepted")
        assert status()["accepted"] == [str(home / "hash # %.txt")]
        print("PASS: hidden files and selecting a file by an encoded URI", flush=True)
        start(0, multiple=True)
        click("fileDialogEntry_first.txt")
        click("fileDialogEntry_second.txt")
        click("fileDialogAccept")
        wait(lambda: not status()["open"], "multiple accepted")
        assert sorted(status()["accepted"]) == sorted([str(home / n) for n in ["first.txt", "second.txt"]])
        print("PASS: multiple file selection", flush=True)
        start(1)
        path(home / "Files with spaces")
        click("fileDialogAccept")
        wait(lambda: not status()["open"], "save accepted")
        assert status()["accepted"] == [str(home / "Files with spaces/saved file.txt")]
        start(2)
        path(home / "Каталог")
        click("fileDialogAccept")
        wait(lambda: not status()["open"], "folder accepted")
        assert status()["accepted"] == [str(home / "Каталог")]
        print("PASS: Save As and selecting a directory", flush=True)
        start(0)
        wait(lambda: any(i["status"] == 1 and unquote(i["source"]).endswith("image # %.png")
            for i in status()["icons"]), "encoded thumbnail")
        assert all(i["source"] != "image://icon/" for i in status()["icons"])
        cancel()
        assert status()["cancelled"]
        ctl("eval", 'hl.dispatch(hl.dsp.window.fullscreen_state({window="title:^File dialog test underlay$",internal=2,client=2,action="set"}))')
        start(1)
        path(home / "Files with spaces")
        click("fileDialogAccept")
        wait(lambda: not status()["open"], "fullscreen save accepted")
        assert status()["accepted"] == [str(home / "Files with spaces/saved file.txt")]
        assert json.loads(ctl("-j", "clients"))[0]["fullscreen"] == 2
        print("PASS: Save As remains visible and accepts input above an exclusive fullscreen application", flush=True)
        start(0)
        wait(lambda: status()["preferencesLoaded"], "view preferences")
        click("fileDialogEntry_first.txt")
        click("fileDialogListView")
        wait(lambda: status()["viewMode"] == "list", "list view")
        assert status()["selected"] == [str(home / "first.txt")]
        click("fileDialogSort_modified")
        wait(lambda: status()["sortBy"] == "modified" and status()["reverse"], "newest first")
        wait(lambda: status()["files"] == ["image # %.png", "second.txt", "hash # %.txt", "first.txt"], "date-sorted rows")
        assert status()["selected"] == [str(home / "first.txt")]
        click("fileDialogSort_modified")
        wait(lambda: not status()["reverse"], "oldest first")
        wait(lambda: status()["files"] == ["first.txt", "hash # %.txt", "second.txt", "image # %.png"], "reversed date-sorted rows")
        for field in ["size", "type", "name"]:
            click("fileDialogSort_" + field)
            wait(lambda: status()["sortBy"] == field, "sort " + field)
            assert status()["selected"] == [str(home / "first.txt")]
            wait(lambda: status()["current"] == str(home / "first.txt"), "keyboard focus follows selected file")
        snapshot("filechooser-list.png")
        click("fileDialogIconsView")
        wait(lambda: status()["viewMode"] == "icons", "icons view")
        assert status()["selected"] == [str(home / "first.txt")]
        click("fileDialogListView")
        click("fileDialogSort_modified")
        cancel()
        start(1)
        assert status()["viewMode"] == "list" and status()["sortBy"] == "modified" and status()["reverse"]
        cancel()
        settings_file = prefs / "file-dialog.json"
        wait(lambda: settings_file.exists() and json.loads(settings_file.read_text()) ==
            {"viewMode":"list", "sortBy":"modified", "reverse":True}, "persisted view preferences")
        shell_proc.terminate()
        shell_proc.wait(timeout=10)
        shell_proc = launch([qs, "--path", str(shell), "--no-duplicate", "--no-color"], "shell-restored")
        wait(lambda: "File dialog test underlay" in ctl("-j", "clients"), "restored shell")
        start(0)
        wait(lambda: status()["preferencesLoaded"], "restored preferences")
        assert status()["viewMode"] == "list" and status()["sortBy"] == "modified" and status()["reverse"]
        cancel()
        print("PASS: list/icons views, all sort controls, selection preservation and preferences after reopening and shell restart", flush=True)
        assert not ctl("configerrors").strip()
        print("PASS: thumbnails with reserved characters, cancellation and clean compositor config", flush=True)
    finally:
        try: run(["grim", str(base / "last-frame.png")])
        except (OSError, subprocess.SubprocessError): pass
        try: (base / "status.json").write_text(ipc("status"))
        except (OSError, subprocess.SubprocessError): pass
        for child in reversed(children):
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(child.pid, signal.SIGKILL)
        if focused.get("address"):
            subprocess.run(["hyprctl", "eval", 'hl.dispatch(hl.dsp.focus({window='
                + json.dumps("address:" + focused["address"]) + '}))'], env=parent,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
