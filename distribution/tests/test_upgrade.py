#!/usr/bin/env python3
"""Exercise native module migration and the secondary overlay in a nested session.

Run with HYPRSTACK_TEST_PREFIX pointing at a pristine staged installation.
Requires Hyprland 0.57, kitty and an existing Wayland session.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2] / "shell"


def main():
    prefix = Path(os.environ["HYPRSTACK_TEST_PREFIX"])
    plugin = prefix / "share/hyprstack/native/hyprstack-bars.so"
    assert plugin.is_file(), plugin
    base = Path(tempfile.mkdtemp(prefix="hs-upg-"))
    print("Artifacts:", base, flush=True)
    home, runtime = base / "home", base / "r"
    home.mkdir()
    runtime.mkdir(mode=0o700)
    config = home / ".config"
    shutil.copytree(ROOT / "assets/hyprland/config", config / "hypr")
    prefs = config / "hyprstack"
    prefs.mkdir()
    native = home / ".local/share/hyprstack/native"
    native.mkdir(parents=True)
    (native / "hyprstack-bars.so").symlink_to(plugin)
    probe = base / "damage-probe.so"
    flags = subprocess.check_output(["pkg-config", "--cflags", "hyprland", "pixman-1", "libdrm",
        "libinput", "libudev", "wayland-server", "xkbcommon", "lua"], text=True).split()
    subprocess.run(["c++", "-std=c++23", "-shared", "-fPIC", "-fno-gnu-unique", *flags,
        str(Path(__file__).with_name("damage_probe.cpp")), "-o", str(probe)], check=True)
    # A pre-upgrade snapshot must never win over the freshly built module.
    legacy = native / "hyprstack-bars-desktop-fixes-old.so"
    legacy.write_bytes(b"incompatible pre-upgrade module\n")
    (prefs / "titlebars.json").write_text(json.dumps({"path": str(legacy)}))
    (prefs / "workspaces.json").write_text(json.dumps({"per_monitor": True, "count": 10,
        "monitor_bases": {"WAYLAND-1": 0, "UPGRADE-2": 20},
        "secondary_monitor": "UPGRADE-2", "secondary_on_special": True, "initialized": True}))
    (prefs / "layouts.json").write_text('{"mode":"scrolling"}\n')
    (prefs / "hypr-user.lua").write_text(
        'dofile(' + json.dumps(str(ROOT / "assets/hyprland/layouts.lua")) + ')\n'
        'hl.monitor({output="",mode="1280x800@60",position="0x0",scale=1})\n'
        'hl.monitor({output="UPGRADE-2",mode="1280x800@60",position="1280x0",scale=1})\n'
        'hl.config({input={follow_mouse=0},cursor={no_warps=true}})\n')
    entry = base / "hyprland.lua"
    entry.write_text('local on=hl.on; hl.on=function(name,callback) '
        'if name~="hyprland.start" then return on(name,callback) end end\n'
        'dofile(' + json.dumps(str(config / "hypr/hyprland.lua")) + ')\nhl.on=on\n')
    parent = dict(os.environ)
    display = parent["WAYLAND_DISPLAY"]
    if not display.startswith("/"):
        display = str(Path(parent["XDG_RUNTIME_DIR"]) / display)
    env = dict(parent, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
        XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(home / ".local/share"),
        XDG_STATE_HOME=str(home / ".local/state"), XDG_CACHE_HOME=str(home / ".cache"),
        WAYLAND_DISPLAY=display, AQ_DRM_DEVICES="/dev/null", HYPRSTACK_NESTED="1")
    for key in ("HYPRLAND_INSTANCE_SIGNATURE", "HYPRSTACK_TITLEBAR_PLUGIN", "HYPRSTACK_DATA_DIR",
                "LIBGL_ALWAYS_SOFTWARE", "__EGL_VENDOR_LIBRARY_FILENAMES"):
        env.pop(key, None)
    children = []

    def launch(args, name):
        with (base / (name + ".log")).open("w") as log:
            process = subprocess.Popen(args, env=env, stdout=log, stderr=log, start_new_session=True)
        children.append(process)
        return process

    def wait(check, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            result = check()
            if result:
                return result
            time.sleep(.05)
        raise AssertionError("Timed out: " + label)

    def ctl(*args, host=False):
        return subprocess.check_output(["hyprctl", *args], env=parent if host else env,
            text=True, stderr=subprocess.DEVNULL, timeout=5).strip()

    def evaluate(code):
        return ctl("eval", code)

    def clients():
        return {w["title"]: w for w in json.loads(ctl("-j", "clients"))}

    def fit_outputs():
        for w in json.loads(ctl("-j", "clients", host=True)):
            if w["pid"] == compositor.pid:
                ctl("eval", 'local w=hl.get_window(' + json.dumps("address:" + w["address"]) + '); '
                    'hl.dispatch(hl.dsp.window.float({window=w,action="enable"})); '
                    'hl.dispatch(hl.dsp.window.resize({window=w,x=1280,y=800,relative=false}))', host=True)
        if focused.get("address"):
            ctl("eval", 'hl.dispatch(hl.dsp.focus({window=' + json.dumps("address:" + focused["address"]) + '}))', host=True)

    focused = json.loads(ctl("-j", "activewindow", host=True))
    try:
        compositor = launch(["Hyprland", "-c", str(entry)], "compositor")
        socket = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        wait(lambda: any(p["name"] == "hyprstack-hyprbars" for p in json.loads(ctl("-j", "plugin", "list"))), "current native module")
        wait(lambda: any(w["pid"] == compositor.pid for w in json.loads(ctl("-j", "clients", host=True))), "host window")
        fit_outputs()
        ctl("output", "create", "wayland", "UPGRADE-2")
        wait(lambda: len(json.loads(ctl("-j", "monitors"))) == 2, "two outputs")
        fit_outputs()
        for title, workspace in (("UpgradePrimary", "1"), ("UpgradeSecondary", "21")):
            evaluate('hl.dispatch(hl.dsp.focus({workspace=' + json.dumps(workspace) + '}))')
            launch(["kitty", "--class", "upgrade-test", "--title", title, "-e", "sleep", "300"], title)
            wait(lambda: clients().get(title), title)
        time.sleep(.4)
        for title in ("UpgradePrimary", "UpgradeSecondary"):
            w = clients()[title]
            monitor = next(m for m in json.loads(ctl("-j", "monitors")) if m["id"] == w["monitor"])
            assert .35 * monitor["width"] < w["size"][0] < .6 * monitor["width"], w
            assert w["fullscreen"] == 0 and w["fullscreenClient"] == 0, w
        print("PASS: legacy snapshot pin loads the current module; terminals open at half width", flush=True)
        ctl("plugin", "load", str(probe))
        time.sleep(.5)
        regions = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.damage("UpgradePrimary")'))
        assert regions["full"][2] > 100 and regions["full"][3] > 100, regions
        assert regions["bounded"] == [0, 0, 17, 13] and regions["empty"] == [0, 0, 0, 0], regions
        print("PASS: full, partial and empty client damage regions retain their exact bounds", flush=True)
        evaluate('hl.dispatch(hl.dsp.focus({monitor="WAYLAND-1"}))')
        original = clients()["UpgradeSecondary"]
        for cycle in range(20):
            evaluate('hyprstack_layouts.toggle_special()')
            wait(lambda: clients()["UpgradeSecondary"]["workspace"]["type"] == "special", "secondary overlay")
            if cycle == 10:
                ctl("reload")
                # Reload is a recovery point: it returns borrowed windows.
            else:
                evaluate('hyprstack_layouts.toggle_special()')
            wait(lambda: clients()["UpgradeSecondary"]["workspace"].get("id") == 21, "secondary restore")
        time.sleep(.4)
        restored = clients()["UpgradeSecondary"]
        assert (restored["at"], restored["size"]) == (original["at"], original["size"]), (original, restored)
        assert ctl("configerrors") == "", ctl("configerrors")
        print("PASS: 20 overlay cycles, reload while open, exact geometry restore and no Lua errors", flush=True)
        ctl("plugin", "unload", str(native / "hyprstack-bars.so"))
        ctl("plugin", "load", str(native / "hyprstack-bars.so"))
        time.sleep(.5)
        regions = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.damage("UpgradePrimary")'))
        assert regions["bounded"] == [0, 0, 17, 13] and ctl("configerrors") == "", regions
        print("PASS: module replacement without restarting the compositor preserves client damage", flush=True)
    finally:
        for process in reversed(children):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
        if focused.get("address"):
            ctl("eval", 'hl.dispatch(hl.dsp.focus({window=' + json.dumps("address:" + focused["address"]) + '}))', host=True)


if __name__ == "__main__":
    main()
