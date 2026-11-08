#!/usr/bin/env python3
"""Pixel checks for stale first buffers and translucent fullscreen backdrops.

HYPRSTACK_TEST_PREFIX must point at a staged installation. Requires Hyprland,
an existing Wayland session, wayland-scanner, wayland-protocols, a C compiler,
grim and Pillow. All captured pixels belong to the synthetic nested desktop.
Set HYPRSTACK_TEST_BACKGROUND_ONLY=1 for fullscreen background/layer checks;
that mode additionally requires Quickshell.
"""
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
from PIL import Image


def main():
    prefix = Path(os.environ["HYPRSTACK_TEST_PREFIX"])
    native = os.environ.get("HYPRSTACK_TEST_NATIVE", str(prefix / "share/hyprstack/native/hyprstack-bars.so"))
    source = prefix / "share/hyprstack/shell"
    base = Path(tempfile.mkdtemp(prefix="hs-media-"))
    print("Artifacts:", base, flush=True)
    protocol = Path(subprocess.check_output(["pkg-config", "--variable=pkgdatadir", "wayland-protocols"], text=True).strip()) / "stable/xdg-shell/xdg-shell.xml"
    for mode, target in [("client-header", "xdg-shell.h"), ("private-code", "xdg-shell.c")]:
        subprocess.run(["wayland-scanner", mode, str(protocol), str(base / target)], check=True)
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "wayland-client"], text=True))
    client = base / "media-client"
    subprocess.run(["cc", "-std=c11", "-I" + str(base), str(Path(__file__).with_name("media_viewer_client.c")),
                    str(base / "xdg-shell.c"), *flags, "-o", str(client)], check=True)
    home, runtime = base / "home", base / "r"
    home.mkdir(); runtime.mkdir(mode=0o700)
    config = home / ".config"
    shutil.copytree(source / "assets/hyprland/config", config / "hypr")
    prefs = config / "hyprstack"
    prefs.mkdir()
    (prefs / "hypr-user.lua").write_text('dofile(' + json.dumps(str(source / "assets/hyprland/layouts.lua")) + ')\n'
        'hl.monitor({output="",mode="1280x800@60",position="0x0",scale=1})\n'
        'hl.config({input={follow_mouse=0},cursor={no_warps=true}})\n')
    (prefs / "tiling.json").write_text('{"focusOnHover":false,"edgeScroll":false}\n')
    entry = base / "hyprland.lua"
    entry.write_text('local on=hl.on;hl.on=function(n,f) if n~="hyprland.start" then return on(n,f) end end\n'
        'dofile(' + json.dumps(str(config / "hypr/hyprland.lua")) + ')\nhl.on=on\n')
    parent = dict(os.environ)
    display = Path(parent["WAYLAND_DISPLAY"])
    if not display.is_absolute(): display = Path(parent["XDG_RUNTIME_DIR"]) / display
    env = dict(parent, HOME=str(home), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(config),
        XDG_DATA_HOME=str(home / ".local/share"), XDG_STATE_HOME=str(home / ".local/state"),
        XDG_CACHE_HOME=str(home / ".cache"), WAYLAND_DISPLAY=str(display), AQ_DRM_DEVICES="/dev/null",
        HYPRSTACK_NESTED="1", HYPRSTACK_DATA_DIR=str(prefix / "share/hyprstack"),
        HYPRSTACK_TITLEBAR_PLUGIN=native)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    children = []
    def run(*args, host=False):
        return subprocess.check_output(args, env=parent if host else env, text=True, timeout=10).strip()
    def ctl(*args): return run("hyprctl", *args)
    def evaluate(code): return ctl("eval", code)
    def clients(): return {w["title"]: w for w in json.loads(ctl("-j", "clients"))}
    def wait(check, label):
        until = time.monotonic() + 15
        while time.monotonic() < until:
            value = check()
            if value: return value
            time.sleep(.03)
        raise AssertionError("Timed out: " + label)
    def launch(args, name, stdin=None):
        with (base / (name + ".log")).open("w") as log:
            child = subprocess.Popen(args, env=env, stdin=stdin, stdout=log, stderr=log, start_new_session=True)
        children.append(child)
        return child
    def image(name):
        path = base / (name + ".png")
        run("grim", "-o", "WAYLAND-1", str(path))
        return Image.open(path).convert("RGB")
    focused = json.loads(run("hyprctl", "-j", "activewindow", host=True))
    try:
        compositor = launch(["Hyprland", "-c", str(entry)], "compositor")
        sock = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sock.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        wait(lambda: "hyprstack-hyprbars" in ctl("-j", "plugin", "list"), "native module")
        outer = wait(lambda: next((w for w in json.loads(run("hyprctl", "-j", "clients", host=True))
                                   if w["pid"] == compositor.pid), None), "nested output")
        selector = json.dumps("address:" + outer["address"])
        run("hyprctl", "eval", 'hl.dispatch(hl.dsp.window.float({window=' + selector + ',action="enable"})); '
            'hl.dispatch(hl.dsp.window.resize({window=' + selector + ',x=1280,y=800,relative=false}))', host=True)
        if focused.get("address"):
            run("hyprctl", "eval", 'hl.dispatch(hl.dsp.focus({window='
                + json.dumps("address:" + focused["address"]) + '}))', host=True)
        fixture = launch([str(client)], "client", subprocess.PIPE)
        wait(lambda: clients().get("AyuGram"), "chat")
        if os.environ.get("HYPRSTACK_TEST_BACKGROUND_ONLY") == "1":
            # Start a shell background while a real fullscreen client exists.
            # Older compositors leave that layer permanently at fade alpha 0.
            evaluate('hl.config({layers={allow_new_top_layers_over_existing_fullscreen=false}})')
            fixture.stdin.write(b"o"); fixture.stdin.flush()
            wait(lambda: clients().get("Media viewer", {}).get("fullscreen") == 2, "fullscreen viewer")
            shell_dir = base / "background-shell"
            shell_dir.mkdir()
            (shell_dir / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
ShellRoot {
    settings.watchFiles: false
    PanelWindow {
        id: backgroundWindow
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#204020"
        WlrLayershell.namespace: "hyprstack-background"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
    }
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: 20
        color: "#d08020"
        WlrLayershell.namespace: "test-background-top"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
    }
    PanelWindow {
        id: dialog
        screen: Quickshell.screens[0]
        visible: false
        implicitWidth: 400
        implicitHeight: 200
        color: "#cccccc"
        WlrLayershell.namespace: "test-background-dialog"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
    }
    IpcHandler {
        target: "backgroundTest"
        function open(): void { dialog.visible = true; }
        function close(): void { dialog.visible = false; }
        function wallpaper(enabled: bool): void {
            backgroundWindow.WlrLayershell.layer = enabled ? WlrLayer.Background : WlrLayer.Bottom;
        }
    }
}
''')
            qs = os.environ.get("HYPRSTACK_TEST_QS", "qs")
            launch([qs, "--path", str(shell_dir), "--no-duplicate", "--no-color"], "background-shell")
            def layer(name):
                return next((dict(layer, level=key) for monitor in json.loads(ctl("-j", "layers")).values()
                    for key,level in monitor["levels"].items() for layer in level if layer["namespace"] == name), None)
            def shell_call(method, *args):
                return run(qs, "ipc", "-p", str(shell_dir), "call", "--", "backgroundTest", method, *args)
            wait(lambda: layer("hyprstack-background"), "background layer")
            time.sleep(.6)
            assert layer("hyprstack-background")["alpha"] == 1, "background stays invisible after mapping during fullscreen"
            assert layer("test-background-top")["alpha"] == 0, "TOP panel must stay hidden during fullscreen"
            print("PASS: background mapped during fullscreen is visible; TOP panels stay hidden", flush=True)
            shell_call("wallpaper", "false")
            wait(lambda: layer("hyprstack-background")["level"] == "1", "bottom layer")
            shell_call("wallpaper", "true")
            wait(lambda: layer("hyprstack-background")["level"] == "0" and layer("hyprstack-background")["alpha"] == 1,
                 "wallpaper re-enabled during fullscreen")
            print("PASS: enabling the wallpaper during fullscreen restores its layer", flush=True)
            shell_call("open")
            wait(lambda: layer("test-background-dialog") and layer("test-background-dialog")["alpha"] == 1, "exclusive dialog")
            assert layer("test-background-top")["alpha"] == 0
            shell_call("close")
            print("PASS: exclusive overlay dialogs stay visible while TOP panels remain hidden", flush=True)
            fixture.stdin.write(b"c"); fixture.stdin.flush()
            wait(lambda: "Media viewer" not in clients(), "closed fullscreen viewer")
            evaluate('hl.dispatch(hl.dsp.focus({workspace="3"}))')
            time.sleep(.6)
            assert layer("hyprstack-background")["alpha"] == 1
            pixel = image("wallpaper-after-fullscreen").getpixel((640,400))
            assert max(abs(a-b) for a,b in zip(pixel,(32,64,32))) < 5, pixel
            print("PASS: wallpaper pixels remain visible on the desktop after fullscreen closes", flush=True)
            return
        for mode in ["scrolling", "stacking"]:
            evaluate('if hyprstack_layouts.mode()~=' + json.dumps(mode) + ' then hyprstack_layouts.toggle() end')
            if mode == "scrolling": evaluate('hl.dispatch(hl.dsp.layout("colresize 1.0"))')
            time.sleep(.5)
            chat = clients()["AyuGram"]
            point = (round(chat["at"][0] + chat["size"][0] * .5), round(chat["at"][1] + chat["size"][1] * .85))
            before = image(mode + "-before")
            baseline = before.getpixel(point)
            log = base / "client.log"
            ready_count = log.read_text().count("ready\n")
            fixture.stdin.write(b"o"); fixture.stdin.flush()
            wait(lambda: clients().get("Media viewer", {}).get("fullscreen") == 2, "fullscreen viewer")
            pending = image(mode + "-pending")
            assert log.read_text().count("ready\n") == ready_count, "The stale-buffer screenshot missed its deadline"
            # Ignore Hyprland's red development-launch banner at the top edge.
            colors = pending.crop((0, 40, pending.width, pending.height)).getcolors(1280*800)
            red = sum(count for count,(r,g,b) in colors if r > 180 and g < 35 and b < 35)
            assert red == 0, (mode, "stale red preview was rendered", red)
            assert max(abs(a-b) for a,b in zip(pending.getpixel(point), baseline)) < 5, (mode, "chat hidden before the first ready frame", pending.getpixel(point), baseline)
            wait(lambda: log.read_text().count("ready\n") > ready_count, "ready buffer")
            time.sleep(.45)
            ready = image(mode + "-ready")
            center = ready.getpixel((640,400))
            backdrop = ready.getpixel(point)
            assert center[1] > 150 and center[0] < 20, (mode, "photo", center)
            assert backdrop[2] > backdrop[0]*1.5 and backdrop[2] < baseline[2]*.95, (mode, "dimmed chat backdrop", backdrop, baseline)
            print("PASS:", mode, "hides the stale buffer and retains the chat under the translucent viewer", flush=True)
            fixture.stdin.write(b"c"); fixture.stdin.flush()
            wait(lambda: "Media viewer" not in clients(), "closed viewer")
            time.sleep(.5)
            after = image(mode + "-after").getpixel(point)
            assert max(abs(a-b) for a,b in zip(after, baseline)) < 5, (mode, "chat not restored", after, baseline)
            print("PASS:", mode, "restores the chat after the viewer closes", flush=True)
            # Cancel before a correctly sized frame exists. The close snapshot
            # must not reintroduce the stale image for one frame.
            fixture.stdin.write(b"q"); fixture.stdin.flush()
            wait(lambda: clients().get("Media viewer", {}).get("fullscreen") == 2, "unready viewer")
            fixture.stdin.write(b"c"); fixture.stdin.flush()
            wait(lambda: "Media viewer" not in clients(), "cancelled unready viewer")
            cancelled = image(mode + "-cancelled")
            colors = cancelled.crop((0,40,cancelled.width,cancelled.height)).getcolors(1280*800)
            assert not any(r > 180 and g < 35 and b < 35 for _,(r,g,b) in colors), mode
            print("PASS:", mode, "closing an unready viewer does not flash its stale snapshot", flush=True)
        assert ctl("configerrors") == ""
    finally:
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
