#!/usr/bin/env python3
"""Exercise migration, window state and rendering in a nested session.

Run with HYPRSTACK_TEST_PREFIX pointing at a pristine staged installation.
Requires Hyprland 0.57, kitty, grim, Pillow and an existing Wayland session.
Set HYPRSTACK_TEST_OVERVIEW_ONLY=1 for the 18 preview-corner image checks.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
from PIL import Image


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
    (prefs / "tiling.json").write_text('{"focusOnHover":false,"edgeScroll":false}\n')
    (prefs / "hypr-user.lua").write_text(
        'dofile(' + json.dumps(str(ROOT / "assets/hyprland/layouts.lua")) + ')\n'
        'hl.monitor({output="",mode="1280x800@60",position="0x0",scale=1})\n'
        'hl.monitor({output="UPGRADE-2",mode="1280x800@60",position="1280x0",scale=1})\n'
        'hl.window_rule({name="upgrade-floating",match={class="^upgrade-floating$"},float=true})\n'
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
        result = ctl("eval", code)
        assert result == "ok", (code, result)
        return result

    def toggle_overlay():
        # Host pointer events must not choose the other nested output while a
        # fixture is exercising a flight from WAYLAND-1.
        return evaluate('hl.dispatch(hl.dsp.focus({monitor="WAYLAND-1"})); hyprstack_layouts.toggle_special()')

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
        executable = base / "Hyprland"
        shutil.copy2(shutil.which("Hyprland"), executable)
        compositor = launch([str(executable), "-c", str(entry)], "compositor")
        socket = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket()), None), "display"))
        wait(lambda: any(p["name"] == "hyprstack-hyprbars" for p in json.loads(ctl("-j", "plugin", "list"))), "current native module")
        # Reproduce a package upgrade: the running inode remains accessible
        # through /proc, while canonical(/proc/self/exe) starts failing.
        # The module replacement at the end must continue to load its hooks.
        executable.unlink()
        ctl("plugin", "unload", str(native / "hyprstack-bars.so"))
        loaded = ctl("plugin", "load", str(native / "hyprstack-bars.so"))
        assert any(p["name"] == "hyprstack-hyprbars" for p in json.loads(ctl("-j", "plugin", "list"))), loaded
        print("PASS: module reload resolves symbols after a package upgrade unlinks the executable", flush=True)
        wait(lambda: any(w["pid"] == compositor.pid for w in json.loads(ctl("-j", "clients", host=True))), "host window")
        fit_outputs()
        if os.environ.get("HYPRSTACK_TEST_RECT_ONLY") == "1":
            ctl("plugin", "load", str(probe))
            evaluate('hl.plugin.upgrade_probe.rectangle("request")')
            wait(lambda: ctl("repl", 'return hl.plugin.upgrade_probe.rectangle("status")') == "3",
                 "opaque and blurred rectangle rendering")
            print("PASS: implicit and explicit rectangle damage, including blur", flush=True)
            return
        ctl("output", "create", "wayland", "UPGRADE-2")
        wait(lambda: len(json.loads(ctl("-j", "monitors"))) == 2, "two outputs")
        fit_outputs()
        for title, workspace in (("UpgradePrimary", "1"), ("UpgradeSecondary", "21")):
            evaluate('hl.dispatch(hl.dsp.focus({workspace=' + json.dumps(workspace) + '}))')
            background = "203070" if title == "UpgradePrimary" else "b43c24"
            launch(["kitty", "--class", "upgrade-test", "--title", title, "-o", "background=#"+background,
                "-o", "background_opacity=1", "-e", "sleep", "300"], title)
            wait(lambda: clients().get(title), title)
        time.sleep(.4)
        for title in ("UpgradePrimary", "UpgradeSecondary"):
            w = clients()[title]
            monitor = next(m for m in json.loads(ctl("-j", "monitors")) if m["id"] == w["monitor"])
            assert .35 * monitor["width"] < w["size"][0] < .6 * monitor["width"], w
            assert w["fullscreen"] == 0 and w["fullscreenClient"] == 0, w

        if os.environ.get("HYPRSTACK_TEST_OVERVIEW_ONLY") == "1":
            evaluate('hl.dispatch(hl.dsp.focus({window="title:^UpgradePrimary$"}))')
            cases = [(mode, radius, zoom) for mode in ["scrolling", "stacking"]
                     for radius in [0, 15, 40] for zoom in [.4, .6, .85]]
            for mode, radius, zoom in cases:
                name = mode + "-" + str(radius) + "-" + str(zoom)
                evaluate('if hyprstack_layouts.mode() ~= ' + json.dumps(mode) + ' then hyprstack_layouts.toggle() end')
                evaluate('hyprstack_layouts.tiling({windowRounding=' + str(radius) +
                    ',focusBorderWidth=3,focusBorderGradient=false}); '
                    'hyprstack_layouts.theme({primary="ff0000",outline="ff0000"})')
                # Keep both contours at least two physical pixels wide even
                # in small stacking previews, so the colour probe is stable.
                evaluate('hl.dispatch(hl.dsp.window.set_prop({window="title:^UpgradePrimary$",prop="border_size",value="4"}))')
                time.sleep(.35)
                window = clients()["UpgradePrimary"]
                world = dict(zip(("x", "y", "width", "height"), [*window["at"], *window["size"]]))
                camera = {"x": 140, "y": 100, "zoom": zoom}
                destination = {"x": camera['x'] + world['x'] * zoom, "y": camera['y'] + world['y'] * zoom,
                               "width": world['width'] * zoom, "height": world['height'] * zoom}
                data = {"monitor": "WAYLAND-1", "mode": mode, "selected": window["address"],
                        "workspace": 1, "originalWorkspace": 1, "camera": camera, "originCamera": camera,
                        "colour": [0, 1, 1], "windows": [{"address": window["address"],
                        "identity": window["stableId"], "workspace": 1, "frame": destination, "world": world}]}
                evaluate('hl.plugin.hyprbars.overview_scene("show",' + json.dumps(json.dumps(data)) + ')')
                time.sleep(.4)
                subprocess.run(["grim", "-o", "WAYLAND-1", str(base / ("overview-" + name + ".png"))], env=env, check=True)
                status = json.loads(ctl("repl", 'return hl.plugin.hyprbars.overview_scene("status")'))
                (base / ("overview-" + name + ".json")).write_text(json.dumps(status, indent=2))
                if os.environ.get("HYPRSTACK_TEST_OVERVIEW_CHECK", "1") != "0":
                    image = Image.open(base / ("overview-" + name + ".png")).convert("RGB")
                    visual = status['frames'][0]['visual']
                    for right, bottom in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                        x = visual['x'] + (visual['width'] - 1) * right
                        y = visual['y'] + (visual['height'] - 1) * bottom
                        cyan, red = [], []
                        for distance in range(-4, 50):
                            rgb = image.getpixel((round(x + (1 - 2 * right) * distance),
                                                  round(y + (1 - 2 * bottom) * distance)))
                            r, g, b = rgb
                            if g > r + 10 and b > r + 10 and abs(g - b) < 15: cyan.append(distance)
                            if r > g + 60 and r > b + 40: red.append(distance)
                        assert cyan, (name, right, bottom, cyan, red)
                        if radius == 0:
                            assert min(cyan) <= 0, (name, right, bottom, cyan, red)
                        else:
                            assert red and 0 <= min(red) - max(cyan) <= 3, (name, right, bottom, cyan, red)
                evaluate('hl.plugin.hyprbars.overview_scene("reset")')
            print("PASS: overview corner fixtures captured", flush=True)
            return

        bindings = json.loads(ctl("-j", "binds"))
        assert not any(b["modmask"] == 1 and b["key"].lower() in ("h", "l", "left", "right")
                       for b in bindings), "Shift must remain available for typing and text selection"

        def focused_title():
            return json.loads(ctl("-j", "activewindow")).get("title")

        def focused_monitor():
            return next(m["name"] for m in json.loads(ctl("-j", "monitors")) if m["focused"])

        def focus_window(title):
            evaluate('hl.dispatch(hl.dsp.focus({window="title:^' + title + '$"}))')
            wait(lambda: focused_title() == title, "focus " + title)

        def horizontal(direction, empty=False):
            evaluate('hyprstack_layouts.focus_column(' + str(direction) + (', true)' if empty else ')'))

        focus_window("UpgradePrimary")
        launch(["kitty", "--class", "upgrade-test", "--title", "UpgradeFocus",
            "-o", "confirm_os_window_close=0", "-e", "sleep", "300"], "focus")
        wait(lambda: clients().get("UpgradeFocus"), "second primary column")
        for mode in ("scrolling", "stacking"):
            if mode == "stacking":
                evaluate('hyprstack_layouts.toggle(); '
                    'for title,x in pairs({UpgradePrimary=60,UpgradeFocus=660}) do '
                    'local w=hl.get_window("title:^"..title.."$"); '
                    'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"geometry",x,150,400,300) end')
                time.sleep(.4)
            # The neighboring output stays enabled but its active workspace is empty.
            evaluate('hl.dispatch(hl.dsp.focus({monitor="UPGRADE-2"})); '
                'hl.dispatch(hl.dsp.focus({workspace="22"}))')
            focus_window("UpgradePrimary")
            horizontal(1, True)
            wait(lambda: focused_title() == "UpgradeFocus", mode + " neighboring window")
            horizontal(1)
            assert focused_title() == "UpgradeFocus", "Super+H/L must keep skipping empty outputs"
            horizontal(1, True)
            try:
                wait(lambda: focused_monitor() == "UPGRADE-2" and not focused_title(), mode + " empty output")
            except AssertionError:
                (base / ("focus-" + mode + ".json")).write_text(json.dumps({
                    "clients": clients(), "monitors": json.loads(ctl("-j", "monitors")),
                    "active": json.loads(ctl("-j", "activewindow"))}, indent=2))
                raise
            horizontal(1, True)
            assert focused_monitor() == "UPGRADE-2" and not focused_title(), "No wrap at the outer edge"
            horizontal(-1, True)
            wait(lambda: focused_monitor() == "WAYLAND-1" and focused_title(), mode + " return from empty output")
            evaluate('hl.dispatch(hl.dsp.focus({monitor="UPGRADE-2"})); '
                'hl.dispatch(hl.dsp.focus({workspace="21"}))')
            focus_window("UpgradeFocus")
            horizontal(1, True)
            wait(lambda: focused_title() == "UpgradeSecondary", mode + " occupied output")
            horizontal(-1, True)
            wait(lambda: focused_monitor() == "WAYLAND-1", mode + " return from occupied output")
            focus_window("UpgradePrimary")
            horizontal(-1, True)
            assert focused_title() == "UpgradePrimary" and focused_monitor() == "WAYLAND-1"
        evaluate('hyprstack_layouts.toggle(); '
            'hl.dispatch(hl.dsp.window.close({window=hl.get_window("title:^UpgradeFocus$")}))')
        wait(lambda: "UpgradeFocus" not in clients(), "focus fixture cleanup")
        evaluate('hyprstack_layouts.focus(1,"UPGRADE-2")')
        print("PASS: horizontal focus crosses outputs without wrapping; Shift typing and selection shortcuts remain free", flush=True)
        ctl("plugin", "load", str(probe))

        # Legacy effect files cannot re-enable the removed inner glow.
        evaluate('hyprstack_layouts.window_effects({windowGlow=true,glowOpacity=1,glowSize=100})')
        assert json.loads(ctl("-j", "getoption", "decoration:glow:enabled"))["bool"] is False
        evaluate('hyprstack_layouts.tiling({focusBorderWidth=0,focusBorderColor="primary",'
            'focusBorderGradient=true,focusBorderGradientEndColor="secondary",focusBorderGradientAngle=90}); '
            'hyprstack_layouts.theme({primary="e46876",secondary="7e9cd8",outline="808080"})')
        gradient = json.loads(ctl("-j", "getoption", "general:col.active_border"))["gradient"].lower()
        assert "e6e46876" in gradient and "e67e9cd8" in gradient and "90deg" in gradient, gradient
        assert json.loads(ctl("-j", "getoption", "general:border_size"))["int"] == 0
        evaluate('hyprstack_layouts.toggle()')
        assert json.loads(ctl("-j", "getoption", "general:border_size"))["int"] == 1
        # The scrolling width cannot hide or thicken stacking borders.
        evaluate('hyprstack_layouts.tiling({focusBorderWidth=8})')
        assert json.loads(ctl("-j", "getoption", "general:border_size"))["int"] == 1
        focus_window("UpgradePrimary")
        evaluate('local w=hl.get_window("title:^UpgradePrimary$"); '
            'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"geometry",120,180,500,330)')
        time.sleep(.5)
        subprocess.run(["grim", "-o", "WAYLAND-1", str(base / "gradient-focused.png")], env=env, check=True)
        evaluate('hyprstack_layouts.action("maximize",hl.get_window("title:^UpgradePrimary$").address)')
        time.sleep(.4)
        evaluate('hyprstack_layouts.tiling({focusBorderWidth=3})')

        def window_border(title):
            return json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.geometry(' + json.dumps(title) + ')'))["borderSize"]

        def maximize_cycles(title):
            enlarged = clients()[title]
            assert window_border(title) == 0, title
            cycles = []
            for delay in (0, .06, .5):
                if delay == 0:
                    evaluate('hyprstack_layouts.toggle(); hyprstack_layouts.toggle()')
                else:
                    evaluate('hyprstack_layouts.toggle()')
                    assert window_border(title) == 3, "Tiling must recover its own border width"
                    time.sleep(delay)
                    evaluate('hyprstack_layouts.toggle()')
                time.sleep(.55)
                restored = clients()[title]
                cycles.append({"delay": delay, "before": [enlarged["at"], enlarged["size"]],
                    "after": [restored["at"], restored["size"]], "client": restored["fullscreenClient"],
                    "border": window_border(title)})
            (base / (title + "-maximized-mode-cycles.json")).write_text(json.dumps(cycles, indent=2))
            assert all(item["before"] == item["after"] and item["client"] == 1 and item["border"] == 0 for item in cycles), cycles
            return enlarged

        maximized = maximize_cycles("UpgradePrimary")
        assert maximized["at"][0] == 0 and maximized["size"][0] == 1280, maximized
        subprocess.run(["grim", "-o", "WAYLAND-1", str(base / "gradient-maximized.png")], env=env, check=True)
        evaluate('hyprstack_layouts.action("maximize",hl.get_window("title:^UpgradePrimary$").address)')
        time.sleep(.3)
        assert window_border("UpgradePrimary") == 1
        launch(["kitty", "--class", "thorium-browser", "--title", "UpgradeCSD",
            "-o", "confirm_os_window_close=0", "-e", "sleep", "300"], "csd")
        wait(lambda: clients().get("UpgradeCSD"), "client-decorated maximize fixture")
        evaluate('hyprstack_layouts.action("maximize-set",hl.get_window("title:^UpgradeCSD$").address)')
        time.sleep(.4)
        csd = maximize_cycles("UpgradeCSD")
        assert csd["at"] == [0, 0] and csd["size"] == [1280, 800], csd

        # Match the shell's asynchronous reservations: a top bar and outer frame
        # in scrolling, then a bottom bar without the frame in stacking.
        panel_dir = base / "reservation-shell"
        panel_dir.mkdir()
        zones = "\n".join('PanelWindow { screen: root.output; anchors.' + edge + ': true; '
            'implicitWidth: 1; implicitHeight: 1; color: "transparent"; '
            'exclusiveZone: root.mode === "stacking" ? ' + str(stacked) + ' : ' + str(tiled) + '; }'
            for edge, stacked, tiled in (("top", 0, 60), ("left", 0, 10), ("right", 0, 10), ("bottom", 40, 10)))
        (panel_dir / "shell.qml").write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\n'
            'ShellRoot { id: root; property string mode: "stacking"; '
            'readonly property ShellScreen output: Quickshell.screens.find(s => s.name === "WAYLAND-1") ?? null; '
            'FileView { path: ' + json.dumps(str(prefs / "layouts.json")) + '; watchChanges: true; '
            'onFileChanged: reload(); onLoaded: root.mode = JSON.parse(text()).mode; }\n' + zones + '\n}\n')
        panels = launch(["qs", "--path", str(panel_dir)], "reservation-shell")

        def reservations():
            return next(m["reserved"] for m in json.loads(ctl("-j", "monitors")) if m["name"] == "WAYLAND-1")

        wait(lambda: reservations() == [0, 0, 0, 40], "stacking panel reservations")
        for title in ("UpgradeCSD", "UpgradePrimary"):
            evaluate('hyprstack_layouts.action("maximize-set",hl.get_window("title:^' + title + '$").address)')
            time.sleep(.4)
            maximize_cycles(title)
        evaluate('hyprstack_layouts.action("maximize-unset",hl.get_window("title:^UpgradePrimary$").address)')
        panels.terminate()
        panels.wait(timeout=5)
        wait(lambda: reservations() == [0, 0, 0, 0], "reservation fixture cleanup")
        evaluate('hl.dispatch(hl.dsp.window.close({window=hl.get_window("title:^UpgradeCSD$")}))')
        wait(lambda: "UpgradeCSD" not in clients(), "CSD fixture cleanup")
        print("PASS: maximized windows with native and client decorations keep their full area and no border through layout cycles", flush=True)
        focus_window("UpgradeSecondary")
        time.sleep(.4)
        subprocess.run(["grim", "-o", "WAYLAND-1", str(base / "gradient-inactive.png")], env=env, check=True)
        # Re-resolve saved roles when the current colour scheme changes.
        evaluate('hyprstack_layouts.theme({primary="98bb6c",secondary="e6c384",outline="808080"}); '
            'hyprstack_layouts.tiling({focusBorderGradientAngle=180})')
        gradient = json.loads(ctl("-j", "getoption", "general:col.active_border"))["gradient"].lower()
        assert "e698bb6c" in gradient and "e6e6c384" in gradient and "180deg" in gradient, gradient
        inactive = json.loads(ctl("-j", "getoption", "general:col.inactive_border"))["gradient"].split()
        assert len(inactive) == 2, inactive
        evaluate('hyprstack_layouts.toggle(); '
            'hyprstack_layouts.tiling({focusBorderWidth=1,focusBorderGradient=false,'
            'focusBorderGradientEndColor="secondary",focusBorderGradientAngle=45}); '
            'hyprstack_layouts.theme({})')
        assert json.loads(ctl("-j", "getoption", "general:border_size"))["int"] == 1
        assert len(json.loads(ctl("-j", "getoption", "general:col.active_border"))["gradient"].split()) == 2
        print("PASS: normal stacking borders stay 1 px; focus gradients follow theme colours and angle; inner glow stays disabled", flush=True)

        launch(["kitty", "--class", "upgrade-floating", "--title", "UpgradeFloating", "-e", "sleep", "300"], "floating")
        wait(lambda: clients().get("UpgradeFloating"), "floating secondary window")
        evaluate('local w=hl.get_window("title:^UpgradeFloating$"); '
            'hl.dispatch(hl.dsp.window.move({window=w,workspace="21",follow=false})); '
            'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"geometry",1350,180,440,330)')
        time.sleep(.4)
        print("PASS: legacy snapshot pin loads the current module; terminals open at half width", flush=True)
        time.sleep(.5)
        regions = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.damage("UpgradePrimary")'))
        assert regions["full"][2] > 100 and regions["full"][3] > 100, regions
        assert regions["bounded"] == [0, 0, 17, 13] and regions["empty"] == [0, 0, 0, 0], regions
        print("PASS: full, partial and empty client damage regions retain their exact bounds", flush=True)
        evaluate('hl.plugin.upgrade_probe.rectangle("request")')
        wait(lambda: ctl("repl", 'return hl.plugin.upgrade_probe.rectangle("status")') == "3",
             "opaque and blurred rectangles with implicit and explicit damage")
        print("PASS: rectangle hooks preserve explicit damage and safely default missing damage with blur", flush=True)
        assert json.loads(ctl("-j", "getoption", "binds:drag_center_window"))["bool"] is False
        evaluate('hl.dispatch(hl.dsp.focus({window="title:^UpgradePrimary$"}))')
        time.sleep(.4)
        w = clients()["UpgradePrimary"]
        x, y = w["at"][0] + round(w["size"][0]*.2), w["at"][1] + round(w["size"][1]*.25)
        # A host pointer event must not replace the fixture's grab point
        # between separate IPC requests in the nested compositor.
        grabbed = json.loads(ctl("repl", 'hl.dispatch(hl.dsp.cursor.move({x=' + str(x) + ',y=' + str(y) + '})); '
            'return hl.plugin.upgrade_probe.drag("UpgradePrimary")'))
        assert grabbed["floating"] and max(abs(a-b) for a,b in zip(grabbed["before"], grabbed["after"])) < .01, grabbed
        print("PASS: tiled drag keeps an off-centre grab point under the cursor", flush=True)
        time.sleep(.4)
        for palette, expected in (({"surface":"282828", "surfaceContainerLowest":"1d2021", "surfaceDim":"242424"}, "1d2021"),
                                  ({"surface":"fff8f0", "surfaceContainerLowest":"ffffff", "surfaceDim":"dcd5ce"}, "dcd5ce")):
            evaluate('hyprstack_layouts.theme(' + '{' + ','.join(k+'='+json.dumps(v) for k,v in palette.items()) + '})')
            colour = json.loads(ctl("-j", "getoption", "plugin:hyprbars:bar_color"))["int"]
            assert colour & 0xFFFFFF == int(expected, 16), (palette, colour)
        print("PASS: dark and light schemes choose a titlebar darker than the application surface", flush=True)
        evaluate('hl.dispatch(hl.dsp.focus({monitor="WAYLAND-1"}))')
        original = clients()["UpgradeSecondary"]
        original_float = clients()["UpgradeFloating"]
        for cycle in range(20):
            toggle_overlay()
            wait(lambda: clients()["UpgradeSecondary"]["workspace"]["type"] == "special", "secondary overlay")
            if cycle == 10:
                ctl("reload")
                # Reload is a recovery point: it returns borrowed windows.
            else:
                if cycle == 0:
                    time.sleep(.45)
                toggle_overlay()
                if cycle == 0:
                    frames = []
                    until = time.monotonic() + .5
                    while time.monotonic() < until:
                        frames.append(json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.geometry("UpgradeSecondary")')))
                        time.sleep(.02)
                    assert frames[0]["movingFromMonitor"], frames[0]
                    assert any(abs(f["current"][0]-f["goal"][0]) > 10 for f in frames), frames
                    assert max(abs(a-b) for a,b in zip(frames[-1]["current"],frames[-1]["goal"])) < 1, frames[-1]
                    xs = [f["current"][0] for f in frames]
                    direction = 1 if frames[0]["goal"][0] > xs[0] else -1
                    assert all((b-a)*direction >= -1 for a,b in zip(xs,xs[1:])), xs
                    (base / "secondary-return-flight.json").write_text(json.dumps(frames, indent=2))
            wait(lambda: clients()["UpgradeSecondary"]["workspace"].get("id") == 21, "secondary restore")
            assert clients()["UpgradeFloating"]["workspace"].get("id") == 21
        time.sleep(.4)
        restored = clients()["UpgradeSecondary"]
        assert (restored["at"], restored["size"]) == (original["at"], original["size"]), (original, restored)
        restored_float = clients()["UpgradeFloating"]
        assert (restored_float["at"], restored_float["size"]) == (original_float["at"], original_float["size"]), (original_float, restored_float)
        assert ctl("configerrors") == "", ctl("configerrors")
        print("PASS: 20 overlay cycles, reload while open, exact geometry restore and no Lua errors", flush=True)
        print("PASS: the return flight keeps the source-monitor presentation and moves smoothly to the original box", flush=True)
        toggle_overlay()
        time.sleep(.45)
        toggle_overlay()
        time.sleep(.04)
        before_reopen = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.geometry("UpgradeSecondary")'))
        toggle_overlay()
        after_reopen = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.geometry("UpgradeSecondary")'))
        assert abs(before_reopen["current"][0]-after_reopen["current"][0]) < 120, (before_reopen, after_reopen)
        time.sleep(.5)
        assert clients()["UpgradeSecondary"]["workspace"]["type"] == "special"
        toggle_overlay()
        wait(lambda: clients()["UpgradeSecondary"]["workspace"].get("id") == 21, "restore after reversing flight")
        ctl("reload")
        assert clients()["UpgradeFloating"]["workspace"].get("id") == 21
        print("PASS: reversing the flight preserves position; reload recovers tiled and floating windows", flush=True)
        evaluate('hl.dispatch(hl.dsp.focus({monitor="WAYLAND-1"})); hl.dispatch(hl.dsp.focus({workspace="1"})); '
            'hl.dispatch(hl.dsp.focus({window=hl.get_window("title:^UpgradePrimary$")})); hl.dispatch(hl.dsp.layout("colresize 1.0"))')
        time.sleep(.5)
        before = base / "covering-window.png"
        subprocess.run(["grim", "-o", "WAYLAND-1", str(before)], env=env, check=True)
        background = Image.open(before).convert("RGB").getpixel((400, 600))
        (base / "covering-state.json").write_text(json.dumps({"clients":clients(),
            "monitors":json.loads(ctl("-j","monitors")),"focused":json.loads(ctl("-j","activewindow"))},indent=2))
        assert background[2] > background[0]*1.5, background
        toggle_overlay()
        time.sleep(.5)
        # Slow only this fixture's native movement, so the sampled point stays
        # inside both overlapping windows while the compositor captures a frame.
        evaluate('hl.animation({leaf="windowsMove",enabled=true,speed=20,bezier="windowGeometry"})')
        toggle_overlay()
        position = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.geometry("UpgradeSecondary")'))["current"]
        point = (round(position[0]+position[2]*.4), round(position[1]+position[3]*.6))
        frame = base / "return-over-covering-window.png"
        subprocess.run(["grim", "-o", "WAYLAND-1", str(frame)], env=env, check=True)
        pixel = Image.open(frame).convert("RGB").getpixel(point)
        assert pixel[0] > pixel[1]*1.5 and pixel[0] > pixel[2]*1.5, (point, pixel, position)
        ctl("reload")
        time.sleep(.5)
        print("PASS: a captured return-flight frame stays above the focused full-width window", flush=True)
        failures = []

        def require(condition, label, detail=None):
            if not condition:
                failures.append((label, detail))
                print("FAIL:", label, detail, flush=True)

        def request(title, operation, value=True):
            evaluate('hl.plugin.upgrade_probe.request_state(' + json.dumps(title) + ',' +
                json.dumps(operation) + ',' + str(value).lower() + ')')

        def maximized(title):
            return json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.client_state(' +
                json.dumps(title) + ')'))["maximized"]

        def box(window):
            return window["at"], window["size"]

        for title in ("UpgradePrimary", "UpgradeFloating"):
            original_box = box(clients()[title])
            for value in (True, False):
                request(title, "maximize", value)
                time.sleep(.3)
                current = clients()[title]
                require(box(current) == original_box and current["fullscreen"] == 0 and
                    current["fullscreenClient"] == 0, "titlebar maximize cannot resize scrolling windows",
                    (title, value, original_box, box(current), current["fullscreen"]))
            evaluate('hl.dispatch(hl.dsp.window.fullscreen_state({window=' +
                json.dumps("title:^"+title+"$") + ',internal=0,client=0,action="set"}))')
        if not failures:
            print("PASS: titlebar maximize requests leave tiled and floating scrolling windows unchanged", flush=True)

        evaluate('hl.dispatch(hl.dsp.focus({window="title:^UpgradePrimary$"})); hyprstack_layouts.toggle()')
        time.sleep(.5)
        normal = clients()["UpgradePrimary"]
        require(normal["floating"] and not maximized("UpgradePrimary"),
            "entering stacking publishes the normal client state", normal["fullscreenClient"])
        for cycle in range(2):
            request("UpgradePrimary", "maximize", True)
            time.sleep(.3)
            enlarged = clients()["UpgradePrimary"]
            require(enlarged["size"][0] > normal["size"][0] and enlarged["fullscreenClient"] == 1 and
                maximized("UpgradePrimary"), "client maximize fills the stacking work area", box(enlarged))
            if cycle == 1:
                ctl("reload")
                time.sleep(.3)
                require(maximized("UpgradePrimary"), "reload retains the real maximized client state")
            request("UpgradePrimary", "maximize", False)
            time.sleep(.3)
            restored = clients()["UpgradePrimary"]
            require(box(restored) == box(normal) and restored["fullscreenClient"] == 0 and
                not maximized("UpgradePrimary"), "client unmaximize restores the normal window",
                (box(normal), box(restored), restored["fullscreenClient"]))
        if not failures:
            print("PASS: stacking sends real client state and respects distinct set/unset maximize requests", flush=True)

        evaluate('hl.dispatch(hl.dsp.window.fullscreen_state({window="title:^UpgradePrimary$",internal=2,client=2,action="set"}))')
        time.sleep(.3)
        for value in (True, False):
            request("UpgradePrimary", "maximize", value)
            time.sleep(.15)
            current = clients()["UpgradePrimary"]
            require(current["fullscreen"] == 2 and current["fullscreenClient"] == 2,
                "client maximize echoes preserve exclusive fullscreen", (value, current["fullscreen"], current["fullscreenClient"]))
        evaluate('hl.dispatch(hl.dsp.window.fullscreen_state({window="title:^UpgradePrimary$",internal=0,client=0,action="set"}))')
        time.sleep(.3)
        print("PASS: client maximize/unmaximize echoes retain exclusive fullscreen", flush=True)
        # Native fullscreen has its own layout recovery. Reset this fixture's
        # valid stacking box before exercising minimize's exact restoration;
        # an out-of-bounds box would intentionally be clamped on restore.
        evaluate('local w=hl.get_window("title:^UpgradePrimary$"); '
            'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"geometry",' +
            ','.join(str(v) for v in [*normal["at"], *normal["size"]]) + ')')
        time.sleep(.3)

        # Delay only the workspace hand-off, beyond the visual animation's end.
        # The final offscreen image must stay in effect during this gap.
        evaluate('hyprstack_layouts.action("maximize-unset",hl.get_window("title:^UpgradePrimary$").address)')
        time.sleep(.3)
        normal = clients()["UpgradePrimary"]
        point = (round(normal["at"][0]+normal["size"][0]*.4),
                 round(normal["at"][1]+normal["size"][1]*.6))
        before = base / "before-minimize.png"
        subprocess.run(["grim", "-o", "WAYLAND-1", str(before)], env=env, check=True)
        original_pixel = Image.open(before).convert("RGB").getpixel(point)
        assert original_pixel[2] > original_pixel[0]*1.5 and original_pixel[2] > 70, (point, original_pixel)
        evaluate('local w=hl.get_window("title:^UpgradePrimary$"); '
            'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"to",550,820,180,32,800)')
        time.sleep(.35)
        assert ctl("repl", 'local w=hl.get_window("title:^UpgradePrimary$"); '
            'return hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"busy")') == "false"
        frame = base / "completed-minimize-before-handoff.png"
        subprocess.run(["grim", "-o", "WAYLAND-1", str(frame)], env=env, check=True)
        pixel = Image.open(frame).convert("RGB").getpixel(point)
        require(not (pixel[2] > pixel[0]*1.5 and pixel[2] > 70),
            "a finished minimize never exposes the original full-size window", (point, pixel))
        evaluate('local w=hl.get_window("title:^UpgradePrimary$"); '
            'hl.plugin.hyprbars.animate_window(w.address,w.stable_id,"clear")')
        for cycle in range(3):
            request("UpgradePrimary", "minimize")
            wait(lambda: clients()["UpgradePrimary"]["workspace"]["type"] == "special", "minimized workspace")
            evaluate('hyprstack_layouts.action("restore",hl.get_window("title:^UpgradePrimary$").address)')
            time.sleep(.35)
            require(box(clients()["UpgradePrimary"]) == box(normal),
                "minimize/restore retains stacking geometry", (cycle,box(normal),box(clients()["UpgradePrimary"])))
        request("UpgradePrimary", "minimize")
        time.sleep(.04)
        ctl("reload")
        require(clients()["UpgradePrimary"]["workspace"]["type"] == "special",
            "reload completes a pending minimize")
        evaluate('hyprstack_layouts.action("restore",hl.get_window("title:^UpgradePrimary$").address)')
        time.sleep(.04)
        ctl("reload")
        time.sleep(.35)
        require(box(clients()["UpgradePrimary"]) == box(normal) and ctl("configerrors") == "",
            "reload during restore removes the transformer and preserves the window")
        if not failures:
            print("PASS: minimize holds its final image until hand-off; restore and reload keep exact geometry", flush=True)
        (base / "stacking-regressions.json").write_text(json.dumps(failures, indent=2))
        assert not failures, failures
        evaluate('hyprstack_layouts.toggle()')
        time.sleep(.5)
        # Match Telegram's floating fullscreen viewer: losing activation while
        # an exclusive layer maps used to leave that layer at alpha zero.
        evaluate('hl.dispatch(hl.dsp.focus({monitor="WAYLAND-1"}))')
        viewer = launch(["kitty", "--class", "com.ayugram.desktop", "--title", "Media viewer",
                         "-e", "sleep", "300"], "media-viewer")
        wait(lambda: clients().get("Media viewer"), "floating media viewer")
        evaluate('hl.dispatch(hl.dsp.window.fullscreen_state({window="title:^Media viewer$",internal=2,client=2,action="set"}))')
        wait(lambda: clients()["Media viewer"]["fullscreen"] == 2, "fullscreen media viewer")
        evaluate('hl.plugin.hyprbars.hover_focus(true, 100)')
        modal_dir = base / "modal-shell"
        modal_dir.mkdir()
        (modal_dir / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Wayland
Scope {
    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === "WAYLAND-1")
        WlrLayershell.namespace: "upgrade-modal-dialog"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        implicitWidth: 500
        implicitHeight: 300
        color: "#304050"
    }
}
''')
        modal = launch(["qs", "--path", str(modal_dir)], "modal-shell")
        def modal_layer():
            return next((layer for monitor in json.loads(ctl("-j", "layers")).values()
                         for layer in monitor["levels"]["3"]
                         if layer["namespace"] == "upgrade-modal-dialog"), None)
        wait(modal_layer, "exclusive save dialog")
        evaluate('hl.dispatch(hl.dsp.cursor.move({x=640,y=400}))')
        time.sleep(.3)
        assert modal_layer()["alpha"] == 1, modal_layer()
        assert clients()["Media viewer"]["fullscreen"] == 2
        assert not json.loads(ctl("repl", 'return hl.plugin.hyprbars.hover_focus("status")'))["waiting"]
        modal.terminate()
        modal.wait(timeout=5)
        wait(lambda: modal_layer() is None, "exclusive dialog cleanup")
        viewer.terminate()
        viewer.wait(timeout=5)
        wait(lambda: "Media viewer" not in clients(), "media viewer cleanup")
        print("PASS: dialogs over fullscreen media remain visible; hover focus respects exclusive dialog input", flush=True)
        ctl("plugin", "unload", str(native / "hyprstack-bars.so"))
        ctl("plugin", "load", str(native / "hyprstack-bars.so"))
        time.sleep(.5)
        regions = json.loads(ctl("repl", 'return hl.plugin.upgrade_probe.damage("UpgradePrimary")'))
        assert regions["bounded"] == [0, 0, 17, 13] and ctl("configerrors") == "", regions
        print("PASS: module replacement after unlinking the running executable preserves client damage", flush=True)
    finally:
        if "compositor" in locals():
            (base / "process-status.json").write_text(json.dumps({"compositorExit": compositor.poll()}))
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
