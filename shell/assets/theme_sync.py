#!/usr/bin/env python3
"""Apply a Hyprstack palette to user application settings, reversibly.

The journal stores original values before writing. INI edits and marked blocks
preserve unrelated settings, including edits made while synchronization is on.
No packages are installed and no application is restarted.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


TERMINALS = ("kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole",
             "xfce4Terminal", "gnomeTerminal", "tilix", "xterm")
DEFAULTS = dict.fromkeys(("enabled", "gtk", "qt", "java", "system", "terminals", "liveReload", *TERMINALS), True)
ENV_KEYS = ("GTK_THEME", "QT_QPA_PLATFORMTHEME", "QT_QUICK_CONTROLS_STYLE", "QT_PLUGIN_PATH", "JAVA_TOOL_OPTIONS")
JAVA_OPTION = "-Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel"
ANSI_NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
THRONE_GTK_PLUGIN = Path("/opt/Throne/usr/plugins/platformthemes/libqgtk3.so")


def xdg(kind: str, fallback: str) -> Path:
    return Path(os.environ.get("XDG_" + kind + "_HOME", Path.home() / fallback))


def qt6ct_supports_kde() -> bool:
    directories = [Path(p) for p in os.environ.get("QT_PLUGIN_PATH", "").split(os.pathsep) if p]
    directories += [Path.home() / ".local/lib/qt6/plugins", Path.home() / ".local/lib/qt/plugins",
                    Path("/usr/lib/qt6/plugins"), Path("/usr/lib64/qt6/plugins"),
                    Path("/usr/lib/x86_64-linux-gnu/qt6/plugins")]
    for directory in directories:
        try:
            return b"KDE_COLOR_SCHEME_PATH" in (directory / "platformthemes/libqt6ct.so").read_bytes()
        except OSError:
            continue
    return False


def read_json(path: Path, default: dict) -> dict:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        return default
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object in {path}")
    return value


def options(values: dict | None = None) -> dict:
    if values is None:
        config = read_json(xdg("CONFIG", ".config") / "hyprstack/shell.json", {})
        appearance = config.get("appearance", {})
        if not isinstance(appearance, dict):
            raise ValueError("appearance must be an object")
        values = appearance.get("themeSync", {})
    if not isinstance(values, dict):
        raise ValueError("appearance.themeSync must be an object")
    result = {**DEFAULTS, **{k: v for k, v in values.items() if k in DEFAULTS}}
    if any(not isinstance(v, bool) for v in result.values()):
        raise ValueError("Theme synchronization settings must be booleans")
    return result


def atomic_text(path: Path, content: str, mode: int = 0o644) -> bool:
    # Follow dotfile symlinks without replacing them. Read-only Nix files produce
    # a reported error, rather than being replaced with writable local copies.
    target = path.resolve() if path.is_symlink() else path
    if target.exists():
        if target.read_text() == content:
            return False
        mode = stat.S_IMODE(target.stat().st_mode)
        if not mode & 0o222:
            raise PermissionError(f"Read-only configuration: {path}")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    return True


def ini_lines(text: str, section: str, key: str) -> list[tuple[int, str]]:
    current, result = "", []
    for index, line in enumerate(text.splitlines(keepends=True)):
        header = re.match(r"^\s*\[([^\]]+)\]\s*(?:[#;].*)?$", line)
        if header:
            current = header[1]
        elif current == section and re.match(r"^\s*" + re.escape(key) + r"\s*=", line):
            result.append((index, line))
    return result


def ini_value(text: str, section: str, key: str, replacement: str | None) -> str:
    """Replace only this key, preserving comments, ordering and other keys."""
    lines = text.splitlines(keepends=True)
    matches = ini_lines(text, section, key)
    if matches:
        for index, _ in reversed(matches):
            lines[index:index + 1] = [replacement] if replacement is not None and index == matches[0][0] else []
        return "".join(lines)
    if replacement is None:
        return text
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if not section:
        lines.insert(0, replacement)
        return "".join(lines)
    for index, line in enumerate(lines):
        if re.match(r"^\s*\[" + re.escape(section) + r"\]\s*(?:[#;].*)?$", line):
            lines.insert(index + 1, replacement)
            return "".join(lines)
    return "".join(lines) + ("\n" if lines else "") + f"[{section}]\n" + replacement


def lua_string(value: str) -> str:
    return '"' + "".join({"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r"}.get(c,
        f"\\{ord(c):03d}" if ord(c) < 32 else c) for c in value) + '"'


def command(args: list[str], input: str | None = None) -> str:
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=4)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"{args[0]} exited with {result.returncode}")
    return result.stdout.strip()


def session_matches() -> bool:
    """Do not reach a parent desktop when running with isolated XDG directories."""
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature or os.environ.get("HYPRSTACK_NESTED") == "1" or not shutil.which("hyprctl"):
        return False
    try:
        instance = next(i for i in json.loads(command(["hyprctl", "-j", "instances"])) if i.get("instance") == signature)
        environment = dict(item.split(b"=", 1) for item in (Path("/proc") / str(int(instance["pid"])) / "environ").read_bytes().split(b"\0") if b"=" in item)
        for kind, fallback in (("CONFIG", ".config"), ("DATA", ".local/share"), ("STATE", ".local/state")):
            key = ("XDG_" + kind + "_HOME").encode()
            other = Path(os.fsdecode(environment.get(key, environment[b"HOME"] + b"/" + fallback.encode())))
            if xdg(kind, fallback).resolve() != other.resolve():
                return False
        return True
    except (OSError, ValueError, KeyError, StopIteration, RuntimeError, subprocess.SubprocessError):
        return False


class Sync:
    def __init__(self, settings: dict, live: bool):
        self.settings = settings
        self.config = xdg("CONFIG", ".config")
        self.data = xdg("DATA", ".local/share")
        self.directory = xdg("STATE", ".local/state") / "hyprstack/theme-sync"
        self.journal = self.directory / "journal.json"
        self.state = read_json(self.journal, {"files": {}, "gsettings": {}, "environment": {}})
        self.wanted: set[str] = set()
        self.wanted_settings: set[str] = set()
        self.changed: set[str] = set()
        self.errors: list[str] = []
        self.skipped: list[str] = []
        self.environment: dict[str, str | None] = {}
        # A nested compositor may share its parent's DBus and X11 display.
        self.live = live and session_matches()

    def save(self):
        atomic_text(self.journal, json.dumps(self.state, ensure_ascii=False, indent=2) + "\n", 0o600)

    def attempt(self, name, action):
        try:
            action()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            self.errors.append(f"{name}: {error}")

    def write(self, path: Path, group: str, transform, kind="file", keys=None):
        name = str(path)
        self.wanted.add(name)
        before = path.read_text() if path.exists() else None
        after = transform(before or "")
        if group == "alacritty":
            inline = ini_lines(before or "", "", "colors")
            for key in ("primary", "cursor", "selection", "normal", "bright"):
                inline.extend(ini_lines(before or "", "colors", key))
            if any(line.split("=", 1)[1].lstrip().startswith("{") for _, line in inline):
                raise ValueError("Expand inline TOML colour tables into [colors.*] sections before synchronizing Alacritty")
            try:
                import tomllib
            except ImportError:
                pass  # Python 3.10; generated values still use TOML string syntax.
            else:
                tomllib.loads(after)  # Refuse unsupported inline tables rather than corrupting them.
        record = self.state["files"].setdefault(name, {"group": group, "original": before, "kind": kind})
        if keys:
            record["keys"] = list(dict.fromkeys([*map(tuple, record.get("keys", [])), *keys]))
        record["applied"] = after
        # A crash after writing still leaves sufficient information to restore.
        self.save()
        if atomic_text(path, after):
            self.changed.add(group)

    def file(self, path: Path, group: str, content: str):
        self.write(path, group, lambda _: content)

    def ini(self, path: Path, group: str, sections: dict[str, dict[str, str]]):
        def transform(text):
            for section, values in sections.items():
                for key, value in values.items():
                    text = ini_value(text, section, key, f"{key}={value}\n")
            return text
        self.write(path, group, transform, "ini", [(section, key) for section, values in sections.items() for key in values])

    def block(self, path: Path, group: str, content: str, style="#", prepend=False, tag="theme"):
        start, end = f"{style} >>> Hyprstack {tag} >>>", f"{style} <<< Hyprstack {tag} <<<"
        if style == "/*":
            start, end = start + " */", end + " */"
        block = start + "\n" + content + "\n" + end + "\n"
        def transform(text):
            pattern = re.escape(start) + r"\n.*?" + re.escape(end) + r"\n?"
            if re.search(pattern, text, re.S):
                return re.sub(pattern, lambda _: block, text, count=1, flags=re.S)
            return block + text if prepend else text + ("\n" if text and not text.endswith("\n") else "") + block
        self.write(path, group, transform, "blocks")

    def restore(self, name, record):
        path = Path(name)
        if not path.exists():
            del self.state["files"][name]
            return
        current, original, applied = path.read_text(), record["original"], record["applied"]
        if current == original:
            # The write may have failed, or the user has already restored it.
            del self.state["files"][name]
            self.save()
            return
        if current == applied:
            restored = original
        elif record["kind"] == "ini":
            restored = current
            for section, key in record["keys"]:
                old, last, now = ini_lines(original or "", section, key), ini_lines(applied, section, key), ini_lines(restored, section, key)
                if [v for _, v in now] == [v for _, v in last]:
                    restored = ini_value(restored, section, key, "".join(v for _, v in old) or None)
        elif record["kind"] == "blocks":
            restored = re.sub(r"(?m)^(?:#|--|/\*) >>> Hyprstack [^\n]+ >>>(?: \*/)?\n.*?"
                              r"^(?:#|--|/\*) <<< Hyprstack [^\n]+ <<<(?: \*/)?\n?", "", current, flags=re.S | re.M)
        else:
            self.errors.append(f"{path}: changed outside Hyprstack; kept your file")
            return
        if restored is None:
            path.unlink()
        else:
            atomic_text(path, restored)
        self.changed.add(record["group"])
        del self.state["files"][name]
        self.save()

    def gsetting(self, group: str, schema: str, key: str, value: str):
        if not self.live or not shutil.which("gsettings") or not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            return
        name = schema + " " + key
        self.wanted_settings.add(name)
        before = command(["gsettings", "get", schema, key])
        record = self.state["gsettings"].setdefault(name, {"group": group, "original": before})
        record["applied"] = value
        self.save()
        if before != value:
            command(["gsettings", "set", schema, key, value])
            self.changed.add(group)

    def restore_settings(self):
        if not self.live:
            return
        for name, record in list(self.state["gsettings"].items()):
            if name in self.wanted_settings:
                continue
            def restore():
                schema, key = name.split(" ")
                if command(["gsettings", "get", schema, key]) == record["applied"]:
                    command(["gsettings", "set", schema, key, record["original"]])
                    self.changed.add(record["group"])
                del self.state["gsettings"][name]
                self.save()
            self.attempt(name, restore)

    def gtk(self, c: dict, mode: str, digest: str):
        if self.state.get("gtkPalette") != digest:
            self.state["gtkTheme"] = "Hyprstack-Alt" if self.state.get("gtkTheme") == "Hyprstack" else "Hyprstack"
            self.state["gtkPalette"] = digest
        name = self.state["gtkTheme"]
        for version in (3, 4):
            css = gtk_css(c, version)
            theme = self.data / "themes" / name / f"gtk-{version}.0"
            base = ("Adwaita/gtk-contained" if version == 3 else "Default/Default")
            suffix = ("-dark" if mode == "dark" else "") if version == 3 else "-" + mode
            content = f'@import url("resource:///org/gtk/libgtk/theme/{base}{suffix}.css");\n' + css
            self.file(theme / "gtk.css", "gtk", content)
            self.file(theme / "gtk-dark.css", "gtk", content)
            colors = self.config / f"gtk-{version}.0/hyprstack-colors.css"
            # User CSS is loaded once by GTK. Keep its values symbolic so a
            # theme-name notification can update existing windows as well.
            self.file(colors, "gtk", gtk_css(c, version, symbolic=True))
            self.block(self.config / f"gtk-{version}.0/gtk.css", "gtk",
                       '@import url("hyprstack-colors.css");', "/*")
            self.ini(self.config / f"gtk-{version}.0/settings.ini", "gtk", {"Settings": {
                "gtk-theme-name": name, "gtk-application-prefer-dark-theme": "1" if mode == "dark" else "0"}})
        gtk2 = 'style "hyprstack" {\n'
        for state_name, background, foreground in (("NORMAL", "surface", "onSurface"), ("ACTIVE", "surfaceContainerHigh", "onSurface"),
                ("PRELIGHT", "surfaceContainerHighest", "onSurface"), ("SELECTED", "primary", "onPrimary"), ("INSENSITIVE", "surface", "onSurfaceVariant")):
            for role, color_role in (("bg", background), ("base", background), ("fg", foreground), ("text", foreground)):
                gtk2 += f'  {role}[{state_name}] = "#{c[color_role]}"\n'
        gtk2 += '}\nclass "*" style "hyprstack"\n'
        rc = self.data / "themes" / name / "gtk-2.0/gtkrc"
        self.file(rc, "gtk", gtk2)
        self.block(Path.home() / ".gtkrc-2.0", "gtk", f'include {lua_string(str(rc))}')
        self.attempt("GTK settings", lambda: self.gsetting("gtk", "org.gnome.desktop.interface", "gtk-theme", repr(name)))
        # A nonempty GTK_THEME pins the startup theme and defeats live changes.
        self.environment["GTK_THEME"] = ""

    def qt(self, c: dict, digest: str):
        # QPalette::ColorRole order, including Qt 6 PlaceholderText and Accent.
        roles = ("onSurface", "surfaceContainer", "surfaceBright", "surfaceContainerHighest", "surfaceDim", "surfaceDim",
                 "onSurface", "onSurface", "onSurface", "surface", "surface", "shadow", "primary", "onPrimary", "primary",
                 "tertiary", "surfaceContainerLow", "shadow", "surfaceContainer", "onSurface", "onSurfaceVariant", "primary")
        active = ", ".join("#" + c[role] for role in roles)
        disabled = ", ".join("#" + c["onSurfaceVariant" if role == "onSurface" else role] for role in roles)
        palette = self.config / "hyprstack/theme/qt-colors.conf"
        palette_text = f"[ColorScheme]\nactive_colors={active}\ninactive_colors={active}\ndisabled_colors={disabled}\n"
        self.file(palette, "qt", palette_text)
        kde = kde_colors(c)
        if self.state.get("qtPalette") != digest:
            self.state["qtPaletteSlot"] = 1 - self.state.get("qtPaletteSlot", 0)
            self.state["qtPalette"] = digest
        qt6_palette = self.config / f"hyprstack/theme/qt-colors-{self.state['qtPaletteSlot']}.colors"
        # Plain qt6ct reads ColorScheme; qt6ct-kde also exposes the KDE colour
        # sets to KColorSchemeManager. Both consume the same generated file.
        # Alternating paths invalidates KColorScheme's cached default config.
        self.file(qt6_palette, "qt", palette_text + sections_text(kde))
        for version in (5, 6):
            self.ini(self.config / f"qt{version}ct/qt{version}ct.conf", "qt", {"Appearance": {
                "color_scheme_path": str(qt6_palette if version == 6 else palette), "custom_palette": "true", "style": "Fusion"},
                # Rewriting the config also wakes qt5ct/qt6ct directory watchers.
                "Hyprstack": {"palette": digest}})
            if not shutil.which(f"qt{version}ct"):
                self.skipped.append(f"qt{version}ct: install the platform theme plugin for Qt {version}")
        self.file(self.data / "color-schemes/Hyprstack.colors", "qt", sections_text(kde))
        self.ini(self.config / "kdeglobals", "qt", kde)
        # KColorSchemeManager otherwise replaces qtct's palette with Breeze on
        # non-KDE desktops. Select our shared scheme for KDE applications too.
        self.ini(self.config / "kdeglobals", "qt", {"UiSettings": {
            "ColorScheme": "" if qt6ct_supports_kde() else "Hyprstack"}})
        # qt6ct explicitly accepts the qt5ct plugin key too.
        self.environment.update(QT_QPA_PLATFORMTHEME="qt5ct", QT_QUICK_CONTROLS_STYLE="Fusion")
        local_plugins = [Path.home() / ".local/lib" / directory / "plugins" for directory in ("qt6", "qt")]
        local_plugins = [str(path) for path in local_plugins if any((path / "platformthemes").glob("libqt*ct.so"))]
        if local_plugins:
            original = self.state["environment"].get("QT_PLUGIN_PATH", {}).get("original", os.environ.get("QT_PLUGIN_PATH"))
            self.environment["QT_PLUGIN_PATH"] = os.pathsep.join(dict.fromkeys([p for p in (original or "").split(os.pathsep) if p] + local_plugins))

    def bundled_qt(self):
        # Throne's binary distribution ships an older Qt than the system qtct
        # plugin. Its bundled GTK platform theme can use our GTK colours instead.
        if not THRONE_GTK_PLUGIN.is_file():
            return
        directories = [self.data, *map(Path, os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(os.pathsep))]
        names = {"Throne.desktop", "throne.desktop", "throne-url-handler.desktop"}
        for name in sorted(names):
            source = next((directory / "applications" / name for directory in directories
                           if (directory / "applications" / name).is_file()), None)
            if source is None:
                continue
            path = self.data / "applications" / name
            source_text = source.read_text()
            def transform(text):
                text = text or source_text
                lines = ini_lines(text, "Desktop Entry", "Exec")
                if not lines:
                    return text
                command = lines[0][1].split("=", 1)[1].strip()
                prefix = "env QT_QPA_PLATFORMTHEME=gtk3 "
                if not command.startswith(prefix):
                    text = ini_value(text, "Desktop Entry", "Exec", f"Exec={prefix}{command}\n")
                return text
            self.write(path, "qt-bundled", transform, "ini", [("Desktop Entry", "Exec")])

    def available(self, name: str, executable: str, paths: list[Path]) -> bool:
        if not self.settings[name]:
            return False
        if shutil.which(executable) or any(p.exists() for p in paths):
            return True
        self.skipped.append(name)
        return False

    def terminal(self, selected: str, c: dict, mode: str):
        cfg, generated = self.config, self.config / "hyprstack/theme"
        paths = [cfg / "kitty/kitty.conf"]
        if selected == "kitty" and self.available("kitty", "kitty", paths):
            theme = generated / "kitty.conf"
            content = "\n".join(f"{key} #{c[role]}" for key, role in {
                "background": "surface", "foreground": "onSurface", "cursor": "primary", "cursor_text_color": "onPrimary",
                "selection_background": "primary", "selection_foreground": "onPrimary", "active_tab_background": "primary",
                "active_tab_foreground": "onPrimary", "inactive_tab_background": "surfaceContainer", "inactive_tab_foreground": "onSurfaceVariant",
                **{f"color{i}": f"term{i}" for i in range(16)}}.items()) + "\n"
            self.file(theme, "kitty", content)
            self.block(paths[0], "kitty", f"include {theme}")
        paths = [cfg / "foot/foot.ini"]
        if selected == "foot" and self.available("foot", "foot", paths):
            version = command(["foot", "--version"]) if shutil.which("foot") else ""
            match = re.search(r"(\d+)\.(\d+)\.", version)
            modern = not match or tuple(map(int, match.groups())) >= (1, 26)
            dual = match and tuple(map(int, match.groups())) >= (1, 23)
            colors = {"foreground": c["onSurface"], "background": c["surface"], "cursor": c["surface"] + " " + c["primary"],
                      "selection-foreground": c["onPrimary"], "selection-background": c["primary"],
                      **{f"regular{i}": c[f"term{i}"] for i in range(8)}, **{f"bright{i}": c[f"term{i + 8}"] for i in range(8)}}
            self.ini(paths[0], "foot", {**({"": {"initial-color-theme": mode if modern else "1"}} if modern or dual else {}),
                **{section: colors for section in (("colors-dark", "colors-light") if modern else ("colors", "colors2") if dual else ("colors",))}})
        paths = [cfg / "alacritty/alacritty.toml", cfg / "alacritty.toml", Path.home() / ".alacritty.toml"]
        if selected == "alacritty" and self.available("alacritty", "alacritty", paths):
            self.ini(next((p for p in paths if p.exists()), paths[0]), "alacritty", {
                "colors.primary": {"background": json.dumps("#" + c["surface"]), "foreground": json.dumps("#" + c["onSurface"])},
                "colors.cursor": {"text": json.dumps("#" + c["surface"]), "cursor": json.dumps("#" + c["primary"])},
                "colors.selection": {"text": json.dumps("#" + c["onPrimary"]), "background": json.dumps("#" + c["primary"])},
                **{f"colors.{kind}": {name: json.dumps("#" + c[f"term{i + offset}"]) for i, name in enumerate(ANSI_NAMES)}
                   for kind, offset in (("normal", 0), ("bright", 8))}})
        paths = [cfg / "wezterm/wezterm.lua", Path.home() / ".wezterm.lua"]
        if selected == "wezterm" and self.available("wezterm", "wezterm", paths):
            path = next((p for p in paths if p.exists()), paths[0])
            theme = generated / "wezterm-colors.lua"
            colors = {"foreground": c["onSurface"], "background": c["surface"], "cursor_bg": c["primary"],
                      "cursor_fg": c["surface"], "cursor_border": c["primary"], "selection_bg": c["primary"], "selection_fg": c["onPrimary"]}
            content = "return {\n" + "".join(f"  {k} = {lua_string('#' + v)},\n" for k, v in colors.items())
            for key, offset in (("ansi", 0), ("brights", 8)):
                content += f"  {key} = {{" + ", ".join(lua_string("#" + c[f"term{i + offset}"]) for i in range(8)) + "},\n"
            self.file(theme, "wezterm", content + "}\n")
            self.block(path, "wezterm", "local function _hyprstack_user_config(...)\n", "--", prepend=True, tag="config start")
            self.block(path, "wezterm", "end\nlocal config = _hyprstack_user_config() or {}\n"
                + f"config.colors = dofile({lua_string(str(theme))})\n"
                + f"require('wezterm').add_to_config_reload_watch_list({lua_string(str(theme))})\nreturn config", "--", tag="config end")
        paths = [cfg / "ghostty/config.ghostty", cfg / "ghostty/config"]
        if selected == "ghostty" and self.available("ghostty", "ghostty", paths):
            theme = generated / "ghostty.conf"
            content = "\n".join(f"{key} = #{c[role]}" for key, role in {"background": "surface", "foreground": "onSurface",
                "cursor-color": "primary", "cursor-text": "surface", "selection-background": "primary", "selection-foreground": "onPrimary"}.items())
            content += "\n" + "".join(f"palette = {i}=#{c[f'term{i}']}\n" for i in range(16))
            self.file(theme, "ghostty", content)
            # The extensionless file loads last when both files exist.
            self.block(next((p for p in reversed(paths) if p.exists()), paths[0]), "ghostty", f"config-file = {lua_string(str(theme))}")
        paths = [cfg / "konsolerc", *sorted((self.data / "konsole").glob("*.profile"))]
        if selected == "konsole" and self.available("konsole", "konsole", paths):
            colors = {"General": {"Description": "Hyprstack"}, "Background": {"Color": rgb(c["surface"])}, "Foreground": {"Color": rgb(c["onSurface"])}}
            for i in range(8):
                colors[f"Color{i}"] = {"Color": rgb(c[f"term{i}"])}
                colors[f"Color{i}Intense"] = {"Color": rgb(c[f"term{i + 8}"])}
            self.file(self.data / "konsole/Hyprstack.colorscheme", "konsole", sections_text(colors))
            profiles = list((self.data / "konsole").glob("*.profile"))
            if not profiles:
                profiles = [self.data / "konsole/Hyprstack.profile"]
                self.ini(profiles[0], "konsole", {"General": {"Name": "Hyprstack", "Parent": "FALLBACK/"}})
                self.ini(paths[0], "konsole", {"Desktop Entry": {"DefaultProfile": "Hyprstack.profile"}})
            for profile in profiles:
                self.ini(profile, "konsole", {"Appearance": {"ColorScheme": "Hyprstack"}})
        paths = [cfg / "xfce4/terminal/terminalrc"]
        if selected == "xfce4Terminal" and self.available("xfce4Terminal", "xfce4-terminal", paths):
            self.ini(paths[0], "xfce4Terminal", {"Configuration": {"ColorForeground": "#" + c["onSurface"], "ColorBackground": "#" + c["surface"],
                "ColorCursor": "#" + c["primary"], "ColorSelection": "#" + c["primary"], "ColorSelectionBackground": "#" + c["primary"],
                "ColorSelectionUseDefault": "FALSE", "ColorUseTheme": "FALSE", "ColorPalette": ";".join("#" + c[f"term{i}"] for i in range(16))}})
        paths = [Path.home() / ".Xresources"]
        if selected == "xterm" and self.available("xterm", "xterm", paths):
            content = "\n".join(f"XTerm*{key}: #{c[role]}" for key, role in {"background": "surface", "foreground": "onSurface", "cursorColor": "primary",
                **{f"color{i}": f"term{i}" for i in range(16)}}.items())
            self.block(paths[0], "xterm", content)
        if self.live:
            for name, executable, schema in (("gnomeTerminal", "gnome-terminal", "org.gnome.Terminal"), ("tilix", "tilix", "com.gexperts.Tilix")):
                if selected == name and self.available(name, executable, []):
                    self.attempt(name, lambda n=name, s=schema: self.terminal_profiles(n, s, c))

    def terminal_profiles(self, name: str, schema: str, c: dict):
        values = command(["gsettings", "get", schema + ".ProfilesList", "list"])
        profiles = re.findall(r"'([0-9a-fA-F-]{36})'", values)
        root = "/org/gnome/terminal/legacy/profiles:/:" if name == "gnomeTerminal" else "/com/gexperts/Tilix/profiles/"
        for profile in profiles:
            target = schema + (".Legacy.Profile:" if name == "gnomeTerminal" else ".Profile:") + root + profile + "/"
            for key, value in {"use-theme-colors": "false", "foreground-color": repr("#" + c["onSurface"]),
                    "background-color": repr("#" + c["surface"]), "palette": "[" + ", ".join(repr("#" + c[f"term{i}"]) for i in range(16)) + "]",
                    "cursor-colors-set": "true", "cursor-background-color": repr("#" + c["primary"]),
                    "cursor-foreground-color": repr("#" + c["surface"]), "highlight-colors-set": "true",
                    "highlight-background-color": repr("#" + c["primary"]), "highlight-foreground-color": repr("#" + c["onPrimary"])}.items():
                self.gsetting(name, target, key, value)

    def set_environment(self):
        records = self.state["environment"]
        for key in ENV_KEYS:
            if key in self.environment:
                record = records.setdefault(key, {"original": os.environ.get(key)})
                if key == "JAVA_TOOL_OPTIONS":
                    self.environment[key] = ((record["original"] or "") + " " + JAVA_OPTION).strip()
                record["applied"] = self.environment[key]
            elif key in records:
                self.environment[key] = records.pop(key)["original"]
        active = {k: v["applied"] for k, v in records.items()}
        if active:
            content = "return {\n" + "".join(f"    [{lua_string(k)}] = {lua_string(v)},\n" for k, v in active.items()) + "}\n"
            self.file(self.config / "hyprstack/theme/environment.lua", "environment", content)
        self.save()
        if self.live and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
            for key, value in self.environment.items():
                self.attempt(key, lambda k=key, v=value: command(["hyprctl", "eval", f"hl.env({lua_string(k)}, {lua_string(v or '')})"]))
        if self.live and os.environ.get("DBUS_SESSION_BUS_ADDRESS") and shutil.which("dbus-update-activation-environment") and self.environment:
            self.attempt("Activation environment", lambda: command(["dbus-update-activation-environment", "--systemd",
                *[f"{k}={v or ''}" for k, v in self.environment.items()]]))

    def xresources(self, c: dict | None):
        if not self.live or not os.environ.get("DISPLAY") or not shutil.which("xrdb"):
            return
        text = command(["xrdb", "-query"]) + "\n"
        records = self.state.setdefault("xresources", {})
        values = {"background": "surface", "foreground": "onSurface", "cursorColor": "primary",
                  **{f"color{i}": f"term{i}" for i in range(16)}}
        for key, role in values.items():
            key = "XTerm*" + key
            pattern = r"(?m)^" + re.escape(key) + r":[^\n]*\n?"
            match = re.search(pattern, text)
            before = match[0] if match else None
            if c is not None:
                record = records.setdefault(key, {"original": before})
                replacement = f"{key}:\t#{c[role]}\n"
                record["applied"] = replacement
            elif key in records:
                record = records.pop(key)
                if before != record["applied"]:
                    continue
                replacement = record["original"] or ""
            else:
                continue
            text = re.sub(pattern, lambda _: replacement, text) if match else text + replacement
        self.save()
        command(["xrdb", "-load"], input=text)

    def apply(self, scheme: dict) -> dict:
        enabled = self.settings["enabled"]
        if enabled:
            from theme_manager import validate_colours
            mode = scheme.get("mode", "dark")
            c = validate_colours(scheme["colours"], mode)
            digest = hashlib.sha256(json.dumps([mode, c], sort_keys=True).encode()).hexdigest()[:16]
            if self.settings["gtk"]:
                self.attempt("GTK", lambda: self.gtk(c, mode, digest))
            if self.settings["qt"]:
                self.attempt("Qt", lambda: self.qt(c, digest))
                if self.settings["gtk"]:
                    self.attempt("Bundled Qt applications", self.bundled_qt)
            if self.settings["java"] and self.settings["gtk"]:
                self.environment["JAVA_TOOL_OPTIONS"] = JAVA_OPTION
            if self.settings["system"]:
                self.attempt("System colour preference", lambda: self.gsetting("system", "org.gnome.desktop.interface", "color-scheme", repr("prefer-" + mode)))
            if self.settings["terminals"]:
                for name in TERMINALS:
                    self.attempt(name, lambda n=name: self.terminal(n, c, mode))
        self.set_environment()
        active_groups = ({name for name in ("gtk", "qt", "system") if self.settings[name]} if enabled else set())
        if enabled and self.settings["qt"] and self.settings["gtk"]:
            active_groups.add("qt-bundled")
        if enabled and self.settings["terminals"]:
            active_groups.update(name for name in TERMINALS if self.settings[name])
        if self.state["environment"]:
            active_groups.add("environment")
        for name, record in list(self.state["files"].items()):
            if name not in self.wanted and record["group"] not in active_groups:
                self.attempt(name, lambda n=name, r=record: self.restore(n, r))
        self.restore_settings()
        if "xterm" in self.changed or self.state.get("xresources"):
            self.attempt("X resources", lambda: self.xresources(c if "xterm" in active_groups else None))
        if self.live and self.changed:
            if enabled and self.settings["terminals"] and self.settings["liveReload"]:
                self.attempt("Terminal colours", lambda: update_terminals(c, self.settings))
            if "qt" in self.changed and shutil.which("gdbus") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
                self.attempt("KDE colours", lambda: command(["gdbus", "emit", "--session", "--object-path", "/KGlobalSettings",
                    "--signal", "org.kde.KGlobalSettings.notifyChange", "0", "0"]))
        self.save()
        report = {"changed": sorted(self.changed), "errors": self.errors, "skipped": self.skipped, "environment": self.environment,
                  "enabled": enabled}
        atomic_text(self.directory / "status.json", json.dumps(report, ensure_ascii=False, indent=2) + "\n", 0o600)
        return report


def rgb(value: str) -> str:
    return ",".join(str(int(value[i:i + 2], 16)) for i in (0, 2, 4))


def sections_text(sections: dict) -> str:
    return "\n".join(f"[{name}]\n" + "".join(f"{k}={v}\n" for k, v in values.items()) for name, values in sections.items())


def kde_colors(c: dict) -> dict:
    result = {"General": {"ColorScheme": "Hyprstack", "Name": "Hyprstack", "AccentColor": rgb(c["primary"])}}
    for section, bg, fg in (("Window", "surface", "onSurface"), ("View", "surface", "onSurface"),
            ("Button", "surfaceContainer", "onSurface"), ("Selection", "primary", "onPrimary"),
            ("Tooltip", "surfaceContainerHighest", "onSurface"), ("Complementary", "surfaceContainerLow", "onSurface"),
            ("Header", "surfaceContainer", "onSurface")):
        result["Colors:" + section] = {"BackgroundNormal": rgb(c[bg]), "BackgroundAlternate": rgb(c["surfaceContainerLow"]),
            "ForegroundNormal": rgb(c[fg]), "ForegroundInactive": rgb(c["onSurfaceVariant"]),
            "ForegroundLink": rgb(c["primary"]), "ForegroundVisited": rgb(c["tertiary"]), "ForegroundNegative": rgb(c["error"]),
            "ForegroundNeutral": rgb(c["secondary"]), "ForegroundPositive": rgb(c["success"]),
            "DecorationFocus": rgb(c["primary"]), "DecorationHover": rgb(c["secondary"])}
        if section == "Selection":
            result["Colors:" + section].update(BackgroundAlternate=rgb(c[bg]), ForegroundInactive=rgb(c[fg]),
                **{"Foreground" + kind: rgb(c[role + "Selection"]) for kind, role in (("Link", "klink"), ("Visited", "kvisited"),
                    ("Negative", "knegative"), ("Neutral", "kneutral"), ("Positive", "kpositive"))})
    return result


def gtk_css(c: dict, version: int = 3, *, symbolic: bool = False) -> str:
    roles = {"theme_bg_color": "surface", "theme_fg_color": "onSurface", "theme_base_color": "surface",
        "theme_text_color": "onSurface", "theme_selected_bg_color": "primary", "theme_selected_fg_color": "onPrimary",
        "theme_unfocused_bg_color": "surface", "theme_unfocused_fg_color": "onSurfaceVariant",
        "theme_unfocused_base_color": "surface", "theme_unfocused_text_color": "onSurfaceVariant",
        "theme_unfocused_selected_bg_color": "primaryContainer", "theme_unfocused_selected_fg_color": "onPrimaryContainer",
        "borders": "outlineVariant", "unfocused_borders": "outlineVariant", "warning_color": "secondary", "error_color": "error", "success_color": "success",
        "accent_color": "primary", "accent_bg_color": "primary", "accent_fg_color": "onPrimary",
        "window_bg_color": "surface", "window_fg_color": "onSurface", "view_bg_color": "surface", "view_fg_color": "onSurface",
        "headerbar_bg_color": "surfaceContainer", "headerbar_fg_color": "onSurface", "headerbar_border_color": "outlineVariant",
        "headerbar_backdrop_color": "surfaceContainerLow", "headerbar_shade_color": "shadow",
        "card_bg_color": "surfaceContainerLow", "card_fg_color": "onSurface", "card_shade_color": "shadow",
        "dialog_bg_color": "surfaceContainerHigh", "dialog_fg_color": "onSurface", "popover_bg_color": "surfaceContainerHigh", "popover_fg_color": "onSurface",
        "sidebar_bg_color": "surfaceContainerLow", "sidebar_fg_color": "onSurface", "sidebar_backdrop_color": "surfaceContainerLow",
        "sidebar_border_color": "outlineVariant", "sidebar_shade_color": "shadow", "shade_color": "shadow"}
    palette = "" if symbolic else "".join(f"@define-color hyprstack_{role} #{c[role]};\n" for role in sorted(set(roles.values())))
    variables = ":root {\n" + "".join(f"  --{key.replace('_', '-')}: @hyprstack_{role};\n" for key, role in roles.items()) + "}\n" if version == 4 else ""
    return "/* Generated by Hyprstack. */\n" + palette + "".join(f"@define-color {key} @hyprstack_{role};\n" for key, role in roles.items()) + variables + """
window, dialog, .background { background-color: @window_bg_color; color: @window_fg_color; }
headerbar, .titlebar, menubar, toolbar { background: @headerbar_bg_color; color: @headerbar_fg_color; }
menubar > menuitem { background: transparent; }
menubar > menuitem:hover { background: @accent_bg_color; color: @accent_fg_color; }
entry, textview, textview text, treeview, list, .view { background-color: @view_bg_color; color: @view_fg_color; }
button { background-image: none; background-color: @headerbar_bg_color; color: @window_fg_color; border-color: @borders; }
button:hover { background-color: @card_bg_color; }
button.suggested-action, selection, *:selected { background-color: @accent_bg_color; color: @accent_fg_color; }
menu, menu menuitem, popover, popover contents { background-color: @popover_bg_color; color: @popover_fg_color; }
tooltip, tooltip * { background-color: @dialog_bg_color; color: @dialog_fg_color; }
"""


def update_terminals(c: dict, settings: dict):
    """Send OSC output only to PTYs owned by selected terminals in this session.

    No remote-control permissions or signals are needed. The PTY master fdinfo
    gives the slave index; writing to it feeds terminal output, never shell input.
    """
    names = {"kitty": "kitty", "foot": "foot", "alacritty": "alacritty", "wezterm-gui": "wezterm", "wezterm-mux-server": "wezterm", "ghostty": "ghostty",
             "konsole": "konsole", "xfce4-terminal": "xfce4Terminal", "gnome-terminal-server": "gnomeTerminal", "tilix": "tilix", "xterm": "xterm"}
    sequence = "".join(f"\x1b]4;{i};#{c[f'term{i}']}\x1b\\" for i in range(16))
    sequence += "".join(f"\x1b]{code};#{c[role]}\x1b\\" for code, role in ((10, "onSurface"), (11, "surface"), (12, "primary"), (17, "primary"), (19, "onPrimary")))
    session_key = "HYPRLAND_INSTANCE_SIGNATURE" if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else "WAYLAND_DISPLAY"
    session = os.environ.get(session_key)
    if not session:
        return
    visited = set()
    for process in Path("/proc").iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            executable = (process / "exe").resolve().name.removeprefix(".").removesuffix("-wrapped")
            target = names.get(executable)
            if not target or not settings.get(target):
                continue
            environment = (process / "environ").read_bytes().split(b"\0")
            if f"{session_key}={session}".encode() not in environment:
                continue
            for info in (process / "fdinfo").iterdir():
                match = re.search(r"^tty-index:\s*(\d+)$", info.read_text(), re.M)
                if not match or match[1] in visited:
                    continue
                tty = Path("/dev/pts") / match[1]
                if tty.stat().st_uid != os.getuid() or not stat.S_ISCHR(tty.stat().st_mode):
                    continue
                fd = os.open(tty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
                try:
                    os.write(fd, sequence.encode())
                finally:
                    os.close(fd)
                visited.add(match[1])
        except (OSError, ValueError):
            continue  # A process or PTY may disappear at any point.


def sync_current(settings: dict | None = None, *, live: bool = True) -> dict:
    settings = options(settings)
    directory = xdg("STATE", ".local/state") / "hyprstack/theme-sync"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        scheme = read_json(directory.parent / "scheme.json", {})
        if settings["enabled"] and not scheme.get("colours"):
            return {"changed": [], "errors": [], "skipped": [], "environment": {}, "enabled": True}
        return Sync(settings, live).apply(scheme)


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize application colours with Hyprstack")
    parser.add_argument("--settings-stdin", action="store_true")
    parser.add_argument("--no-live", action="store_true", help="Write files without contacting running applications or DBus")
    args = parser.parse_args()
    try:
        result = sync_current(json.load(sys.stdin) if args.settings_stdin else None, live=not args.no_live)
    except (OSError, ValueError, TypeError, KeyError) as error:
        result = {"errors": [str(error)], "environment": {}}
    print(json.dumps(result, ensure_ascii=False))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
