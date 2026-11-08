#!/usr/bin/env python3
"""Exercise screenshots on a disposable Wayland display and private D-Bus.

Set HYPRSTACK_TEST_PREFIX to a staged installation, HYPRSTACK_TEST_WTYPE to
wtype, and HYPRSTACK_TEST_POINTER to a virtual-pointer click helper accepting
X Y WIDTH HEIGHT (wayland_test_pointer.c, generated wlr virtual-pointer protocol).
Requires a running Wayland session. No input is sent to the real desktop.
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


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1] / "shell"


def main():
    if "--private-bus" not in sys.argv:
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--private-bus"], check=True)
        return
    prefix = Path(os.environ["HYPRSTACK_TEST_PREFIX"])
    pointer = os.environ["HYPRSTACK_TEST_POINTER"]
    wtype = os.environ.get("HYPRSTACK_TEST_WTYPE", "wtype")
    qs = os.environ.get("HYPRSTACK_TEST_QS", "qs")
    parent = dict(os.environ)
    base = Path(tempfile.mkdtemp(prefix="hs-shot-"))
    print("Artifacts:", base, flush=True)
    runtime, home = base / "r", base / "home"
    runtime.mkdir(mode=0o700)
    home.mkdir()
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
    (shell / "shell.qml").symlink_to(HERE / "screenshot_shell.qml")
    entry = base / "hyprland.lua"
    entry.write_text('local on=hl.on; hl.on=function(name,callback) '
        'if name~="hyprland.start" then return on(name,callback) end end\n'
        'dofile(' + json.dumps(str(config / "hypr/hyprland.lua")) + ')\nhl.on=on\n')
    display = Path(parent["WAYLAND_DISPLAY"])
    if not display.is_absolute(): display = Path(parent["XDG_RUNTIME_DIR"]) / display
    env = dict(parent, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
        XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(base / "data"),
        XDG_CACHE_HOME=str(base / "cache"), XDG_STATE_HOME=str(base / "state"),
        HYPRSTACK_SCREENSHOTS_DIR=str(home / "Saved screenshots"),
        HYPRSTACK_TITLEBAR_PLUGIN=str(prefix / "share/hyprstack/native/hyprstack-bars.so"),
        HYPRSTACK_DATA_DIR=str(prefix / "share/hyprstack"),
        HYPRSTACK_LIB_DIR=str(prefix / "share/hyprstack/lib"),
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
        return run([qs, "ipc", "-p", str(shell), "call", "--", "screenshotTest", method, *args])

    def status(): return json.loads(ipc("status"))
    def ctl(*args): return run(["hyprctl", *args])
    def layers(): return [layer for monitor in json.loads(ctl("-j", "layers")).values()
                         for level in monitor["levels"].values() for layer in level]
    def has_layer(name): return any(l["namespace"] == name for l in layers())
    def key(*args): run([wtype, *args])

    def click(name):
        # Let the real entrance/expansion animation finish before hit testing.
        time.sleep(.7)
        pos = wait(lambda: json.loads(ipc("rect", name)), name)
        layer = wait(lambda: next((l for l in layers() if l["namespace"] == pos["namespace"]), None), name + " layer")
        with (base / "clicks.jsonl").open("a") as log:
            log.write(json.dumps({"name": name, "position": pos, "layer": layer}) + "\n")
        run([pointer, str(round(pos["x"] + layer["x"])), str(round(pos["y"] + layer["y"])), "1280", "800"])

    def preview_open():
        wait(lambda: "screenshot" in status()["dialogs"], "screenshot preview")
        wait(lambda: has_layer("hyprstack-screenshot"), "mapped screenshot")
        mark = runtime / ("hyprstack-dialogs-" + env["HYPRLAND_INSTANCE_SIGNATURE"])
        wait(lambda: mark.exists() and mark.read_text().strip() == "1", "close shortcut ownership")

    def preview_closed():
        wait(lambda: not status()["dialogs"], "closed preview")
        assert status()["underlay"], "Closing the preview closed the application underneath"

    focused = json.loads(subprocess.check_output(["hyprctl", "-j", "activewindow"], text=True))
    try:
        compositor = launch(["Hyprland", "-c", str(entry)], "compositor")
        sock = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        # Send the changed display and XDG paths only to this disposable bus.
        subprocess.run(["dbus-update-activation-environment", *[k for k in env
            if k.startswith("XDG_") or k in ["HOME", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
                "DBUS_SYSTEM_BUS_ADDRESS"]]], env=env, check=True)
        shell_proc = launch([qs, "--path", str(shell), "--no-duplicate", "--no-color"], "shell")
        wait(lambda: "Screenshot test underlay" in ctl("-j", "clients"), "shell startup")
        wait(lambda: status()["loaded"], "notification history")
        wait(lambda: "screenshotFreeze" in ctl("globalshortcuts"), "capture shortcut registration")

        # Use the real keybind, picker capture, clipboard helper and notification server.
        key("-M", "logo", "-M", "shift", "-k", "s", "-m", "shift", "-m", "logo")
        wait(lambda: has_layer("hyprstack-area-picker"), "region picker")
        run([pointer, "640", "400", "1280", "800"])
        wait(lambda: len(status()["notifications"]) == 1, "screenshot notification")
        wait(lambda: not has_layer("hyprstack-area-picker"), "picker dismissed")
        assert not status()["dialogs"], status()
        assert "image/png" in run(["wl-paste", "--list-types"])
        image = wait(lambda: next((n["image"] for n in status()["notifications"]
                                  if "/imagecache/notifs/" in n["image"]), None), "cached screenshot")
        captured = Path(status()["notifications"][0]["path"])
        assert Path(image).read_bytes() == captured.read_bytes()
        print("PASS: Win+Shift+S copies the capture, posts a persistent notification and opens no preview", flush=True)

        click("testScreenshotPopup")
        preview_open()
        click("closeScreenshot")
        preview_closed()
        assert not Path(env["HYPRSTACK_SCREENSHOTS_DIR"]).exists()
        print("PASS: notification click opens the preview; X closes it without saving", flush=True)

        ipc("history")
        record = status()["notifications"][0]
        click("notificationScreenshot_" + record["id"])
        preview_open()
        key("-k", "Escape")
        preview_closed()
        print("PASS: history thumbnail opens the preview and Escape closes it", flush=True)

        ipc("history")
        click("notificationAction_open_" + record["id"])
        preview_open()
        key("-M", "logo", "-P", "q", "-s", "150", "-p", "q", "-m", "logo")
        preview_closed()
        print("PASS: Win+Q closes the preview and preserves the underlying application", flush=True)

        # Persist, stop the original sender/server, and remove the /tmp capture.
        run([qs, "ipc", "-p", str(shell), "call", "--", "notifs", "flush"])
        shell_proc.terminate()
        shell_proc.wait(timeout=10)
        captured.unlink()
        shell_proc = launch([qs, "--path", str(shell), "--no-duplicate", "--no-color"], "shell-restored")
        wait(lambda: "Screenshot test underlay" in ctl("-j", "clients"), "restored shell")
        wait(lambda: status()["loaded"] and len(status()["notifications"]) == 1, "restored history")
        assert not status()["dialogs"] and not status()["notifications"][0]["popup"]
        ipc("history")
        click("notificationScreenshot_" + record["id"])
        preview_open()
        print("PASS: the preview reopens from history after restart and removal of the temporary file", flush=True)

        click("saveScreenshotAs")
        wait(lambda: "filechooser" in status()["dialogs"], "Save as")
        key("-k", "Escape")
        wait(lambda: status()["dialogs"] == ["screenshot"], "cancelled Save as")
        click("saveScreenshot")
        preview_closed()
        saved = list(Path(env["HYPRSTACK_SCREENSHOTS_DIR"]).glob("*.png"))
        assert len(saved) == 1 and saved[0].read_bytes() == Path(image).read_bytes()
        assert not status()["error"], status()
        print("PASS: Save as can be cancelled; Save preserves the original image in the configured directory", flush=True)
        key("-M", "logo", "-k", "q", "-m", "logo")
        wait(lambda: not status()["underlay"], "ordinary application close")
        print("PASS: Win+Q still closes ordinary applications once the preview is gone", flush=True)
    finally:
        if "HYPRLAND_INSTANCE_SIGNATURE" in env:
            try:
                (base / "status.json").write_text(ipc("status"))
                for command in ["globalshortcuts", "binds", "devices", "layers", "configerrors"]:
                    (base / (command + ".txt")).write_text(ctl(command))
            except (OSError, subprocess.SubprocessError):
                pass  # A failed shell must not prevent compositor cleanup.
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
