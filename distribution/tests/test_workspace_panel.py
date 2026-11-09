#!/usr/bin/env python3
"""Exercise workspace bar input on a disposable Wayland display and private D-Bus.

Set HYPRSTACK_TEST_PREFIX to a staged installation and HYPRSTACK_TEST_POINTER
to the virtual-pointer helper accepting
X Y WIDTH HEIGHT [up|down] (wayland_test_pointer.c, generated wlr protocol).
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
    qs = os.environ.get("HYPRSTACK_TEST_QS", "qs")
    parent = dict(os.environ)
    base = Path(tempfile.mkdtemp(prefix="hs-ws-"))
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
    (prefs / "workspaces.json").write_text('{"per_monitor":true,"initialized":true,"count":10,"monitor_bases":{"WAYLAND-1":0,"PANEL-2":20}}\n')
    (prefs / "tiling.json").write_text('{"focusOnHover":false,"edgeScroll":false}\n')
    shell = base / "shell"
    shell.mkdir()
    for name in ["services", "components", "modules", "assets", "utils"]:
        (shell / name).symlink_to(SOURCE / name)
    (shell / "shell.qml").symlink_to(HERE / "workspace_panel_shell.qml")
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
        return run([qs, "ipc", "-p", str(shell), "call", "--", "workspaceTest", method, *args])

    def status(): return json.loads(ipc("status"))
    def ctl(*args): return run(["hyprctl", *args])
    focused = json.loads(subprocess.check_output(["hyprctl", "-j", "activewindow"], text=True))
    try:
        compositor = launch(["Hyprland", "-c", str(entry)], "compositor")
        sock = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        subprocess.run(["dbus-update-activation-environment", *[k for k in env
            if k.startswith("XDG_") or k in ["HOME", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SYSTEM_BUS_ADDRESS"]]], env=env, check=True)
        launch([qs, "--path", str(shell), "--no-duplicate", "--no-color"], "shell")
        wait(lambda: "Workspace test client" in ctl("-j", "clients"), "shell startup")
        wait(lambda: len(status()) and len(status()[0].get("entries") or []) == 10, "workspace delegates")
        time.sleep(1)
        def choose(number):
            target = next(w for w in status()[0]["entries"] if w["id"] == number)
            run([pointer,str(round(target["x"])),str(round(target["y"])),"1280","800"])
        for number in [2,5,1,10,1]:
            choose(number)
            wait(lambda: status()[0]["active"] == number,"click workspace " + str(number))
        print("PASS: clicking occupied and empty workspaces",flush=True)
        choose(1)
        time.sleep(.7)
        assert not status()[0]["special"], "Active workspace click opened a special workspace"
        choose(2)
        wait(lambda: status()[0]["active"] == 2,"click after active workspace")
        print("PASS: clicking the active workspace leaves other workspace buttons usable",flush=True)
        def wheel(direction):
            target = status()[0]["entries"][2]
            run([pointer,str(round(target["x"])),str(round(target["y"])),"1280","800",direction])
        for direction,number in [("down",3),("down",4),("up",3),("up",2)]:
            wheel(direction)
            wait(lambda: status()[0]["active"] == number,"scroll to workspace " + str(number))
        print("PASS: wheel switches workspaces in both directions",flush=True)
        for _ in range(4):
            choose(2)
            time.sleep(.15)
            wheel("down")
            wait(lambda: status()[0]["active"] == 3,"wheel after active click")
            choose(2)
            wait(lambda: status()[0]["active"] == 2,"click after wheel")
        print("PASS: alternating repeated clicks and wheel events remains responsive",flush=True)
        ctl("eval", 'hl.monitor({output="PANEL-2",mode="800x1280@60",position="1280x0",scale=1})')
        ctl("output", "create", "headless", "PANEL-2")
        wait(lambda: len(status()) == 2 and all(len(m.get("entries") or []) == 10 for m in status()), "second monitor panel")
        time.sleep(.7)
        def on_monitor(name): return next(m for m in status() if m["screen"] == name)
        def secondary_input(number, direction=None):
            panel = on_monitor("PANEL-2")
            target = next(w for w in panel["entries"] if w["id"] == number)
            run([pointer,str(round(target["x"]+1280)),str(round(target["y"])),"2080","1280", *([direction] if direction else [])])
        for number in [22,29,21]:
            secondary_input(number)
            wait(lambda: on_monitor("PANEL-2")["active"] == number, "secondary workspace click")
            assert on_monitor("WAYLAND-1")["active"] == 2, "Secondary panel changed the other monitor"
        secondary_input(21)
        time.sleep(.3)
        assert not on_monitor("PANEL-2")["special"]
        secondary_input(23,"down")
        wait(lambda: on_monitor("PANEL-2")["active"] == 22, "secondary wheel down")
        secondary_input(23,"up")
        wait(lambda: on_monitor("PANEL-2")["active"] == 21, "secondary wheel up")
        assert on_monitor("WAYLAND-1")["active"] == 2
        print("PASS: clicks and wheel target the panel's monitor, including empty workspaces",flush=True)
    finally:
        for name, command in [("status",None),("layers",["hyprctl","-j","layers"]),("monitors",["hyprctl","-j","monitors"]),("errors",["hyprctl","configerrors"])]:
            try: (base/(name+".json")).write_text(ipc("status") if command is None else run(command))
            except Exception: pass
        for child in reversed(children):
            if child.poll() is None:
                os.killpg(child.pid,signal.SIGTERM)
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(child.pid,signal.SIGKILL)
        if focused.get("address"):
            subprocess.run(["hyprctl","eval",'hl.dispatch(hl.dsp.focus({window='+json.dumps('address:'+focused['address'])+'}))'],env=parent,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

if __name__ == "__main__": main()
