#!/usr/bin/env python3
"""Hyprstack colour schemes and persistent desktop palettes.

Only user-owned files are written. A catalogue read never applies a theme.
"""
from __future__ import annotations

import argparse
import contextlib
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from i18n import _, configure_argparse


ASSETS = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hyprstack"
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "hyprstack"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hyprstack"
HEX = re.compile(r"#?([0-9a-fA-F]{6})\Z")
MODES = ("dark", "light")
PALETTE_VERSION = 3
SOURCE_ROLE = re.compile(r"palette_[A-Za-z][A-Za-z0-9_]{0,95}\Z")


def colour(value: str) -> str:
    match = HEX.fullmatch(value) if isinstance(value, str) else None
    if not match:
        raise ValueError(_('Invalid colour: %1; use #RRGGBB').replace('%1', repr(value)))
    return match[1].lower()


def mix(a: str, b: str, amount: float) -> str:
    return "".join(f"{round(int(a[i:i+2], 16) * (1-amount) + int(b[i:i+2], 16) * amount):02x}"
                   for i in (0, 2, 4))


def luminance(value: str) -> float:
    channels = [int(value[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (.2126, .7152, .0722)))


def contrast(a: str, b: str) -> float:
    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + .05) / (lo + .05)


def on_colour(value: str) -> str:
    return max(("ffffff", "101018"), key=lambda c: contrast(c, value))


def legible(value: str, background: str, minimum: float = 4.5) -> str:
    if contrast(value, background) >= minimum:
        return value
    target = on_colour(background)
    for step in range(1, 101):
        adjusted = mix(value, target, step / 100)
        if contrast(adjusted, background) >= minimum:
            return adjusted
    return target


def palette(seed: dict, mode: str) -> dict[str, str]:
    """Map a source palette to all shell, terminal and application colour roles."""
    if mode not in MODES:
        raise ValueError(_("Theme mode must be dark or light"))
    bg = colour(seed["background"])
    source_fg = colour(seed["foreground"])
    fg = legible(source_fg, mix(bg, source_fg, .10), 5)
    primary = legible(colour(seed["accent"]), bg)
    secondary = legible(colour(seed.get("secondary", seed["accent"])), bg)
    tertiary = legible(colour(seed.get("tertiary", seed.get("secondary", seed["accent"]))), bg)
    error = legible(colour(seed.get("error", "f38ba8" if mode == "dark" else "b91c1c")), bg)
    success = legible(colour(seed.get("success", "a6e3a1" if mode == "dark" else "38761d")), bg)
    muted = legible(mix(fg, bg, .28), mix(bg, fg, .06))
    result = {
        "background": bg, "surface": bg, "onBackground": fg, "onSurface": fg,
        "surfaceDim": mix(bg, "000000", .10 if mode == "dark" else .07),
        "surfaceBright": mix(bg, "ffffff", .12 if mode == "dark" else .02),
        "surfaceContainerLowest": mix(bg, "000000" if mode == "dark" else "ffffff", .10),
        "surfaceContainerLow": mix(bg, fg, .025), "surfaceContainer": mix(bg, fg, .045),
        "surfaceContainerHigh": mix(bg, fg, .065), "surfaceContainerHighest": mix(bg, fg, .085),
        "surfaceVariant": mix(bg, secondary, .12), "onSurfaceVariant": muted,
        "inverseSurface": fg, "inverseOnSurface": bg,
        "outline": legible(mix(bg, fg, .50), bg, 3), "outlineVariant": mix(bg, fg, .20),
        "shadow": "000000", "scrim": "000000", "surfaceTint": primary,
        "neutral_paletteKeyColor": mix(bg, fg, .5),
        "neutral_variant_paletteKeyColor": mix(bg, secondary, .5),
    }
    for role, value in (("primary", primary), ("secondary", secondary), ("tertiary", tertiary),
                        ("error", error), ("success", success)):
        title = role.capitalize()
        container = mix(bg, value, .22 if mode == "dark" else .15)
        result.update({role: value, f"on{title}": on_colour(value),
                       f"{role}Container": container, f"on{title}Container": legible(fg, container)})
        if role in ("primary", "secondary", "tertiary"):
            fixed = mix(value, "ffffff", .65)
            result.update({f"{role}_paletteKeyColor": value, f"{role}Fixed": fixed,
                           f"{role}FixedDim": mix(value, "ffffff", .3),
                           f"on{title}Fixed": on_colour(fixed),
                           f"on{title}FixedVariant": legible(value, fixed)})
    result["inversePrimary"] = legible(primary, fg)
    ansi = seed.get("ansi", [bg, error, success, tertiary, primary, secondary,
                             seed.get("cyan", secondary), fg])
    if not isinstance(ansi, list) or len(ansi) not in (8, 16):
        raise ValueError(_("ANSI palette must have 8 or 16 colours"))
    ansi = [colour(c) for c in ansi]
    for index in range(16):
        result[f"term{index}"] = ansi[index] if index < len(ansi) else mix(ansi[index - 8], fg, .15)
    source = seed.get("palette", {})
    if not isinstance(source, dict):
        raise ValueError(_("Source palette must be an object"))
    for name, value in source.items():
        if not SOURCE_ROLE.fullmatch("palette_" + name):
            raise ValueError(_('Invalid source colour name: %1').replace('%1', repr(name)))
        result["palette_" + name] = colour(value)
    # Keep the original neutral surfaces; readable text is adjusted separately.
    for role, value in seed.get("roles", {}).items():
        if role not in result or role.startswith(("term", "palette_")):
            raise ValueError(_('Invalid shell colour role: %1').replace('%1', repr(role)))
        result[role] = colour(value)
    for surface in ("surface", "surfaceContainerLow", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest"):
        fg = legible(fg, result[surface], 5)
    result.update(onSurface=fg, onBackground=fg, inverseSurface=fg)
    result["onSurfaceVariant"] = legible(result["onSurfaceVariant"], result["surfaceContainerHighest"])
    # Older CLI application templates still use these role names.
    for name, value in zip(("rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
                            "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender"),
                           (secondary, secondary, ansi[5], tertiary, ansi[1], ansi[9] if len(ansi) == 16 else ansi[1],
                            source.get("orange", ansi[3]), ansi[3], ansi[2], ansi[6], ansi[6], ansi[4], ansi[4], tertiary)):
        result[name] = colour(source.get(name, value))
    result.update(text=fg, subtext1=muted, subtext0=result["outline"], base=bg,
                  mantle=result["surfaceContainerLow"], crust=result["surfaceContainerLowest"])
    for index, name in enumerate(("surface0", "surface1", "surface2", "overlay0", "overlay1", "overlay2")):
        result[name] = mix(bg, fg, .1 + index * .08)
    for name in ("text", "subtext1", "subtext0", "base", "mantle", "crust",
                 "surface0", "surface1", "surface2", "overlay0", "overlay1", "overlay2"):
        if name in source:
            result[name] = colour(source[name])
    for role, value in (("link", primary), ("visited", tertiary), ("negative", error),
                        ("neutral", secondary), ("positive", success)):
        result[f"k{role}"] = value
        result[f"k{role}Selection"] = legible(value, result["primaryContainer"])
    return result


REQUIRED = frozenset(palette({"background": "181820", "foreground": "dddddd", "accent": "aabbff"}, "dark"))
SHELL_ROLES = frozenset(k for k in REQUIRED if not k.startswith("k") and k not in {
    "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow", "green", "teal",
    "sky", "sapphire", "blue", "lavender", "text", "subtext1", "subtext0", "base", "mantle", "crust",
    "surface0", "surface1", "surface2", "overlay0", "overlay1", "overlay2"})


def validate_colours(values: dict, mode: str) -> dict[str, str]:
    if not isinstance(values, dict):
        raise ValueError(_("Theme colours must be an object"))
    # An easy three-colour format as well as the complete Hyprstack format.
    if {"background", "foreground", "accent"} <= values.keys():
        return palette(values, mode)
    missing = SHELL_ROLES - values.keys()
    if missing:
        raise ValueError(_('Missing theme colours: %1').replace("%1", ', '.join(sorted(missing))))
    result = palette({"background": values["surface"], "foreground": values["onSurface"],
                      "accent": values["primary"]}, mode)
    for key, value in values.items():
        if key.startswith("palette_") and not SOURCE_ROLE.fullmatch(key):
            raise ValueError(_('Invalid source colour name: %1').replace('%1', repr(key)))
        if key in REQUIRED or SOURCE_ROLE.fullmatch(key):
            result[key] = colour(value)
    return result


def atomic_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(data, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


@functools.lru_cache(maxsize=1)
def builtins() -> list[dict]:
    data = json.loads((ASSETS / "schemes/presets.json").read_text())
    result = []
    for item in data:
        variants = []
        for mode, seed in item["modes"].items():
            border_colours = []
            for accent in item.get("borderAccents", []):
                values = item["accents"][accent]
                source = next(name for name, value in seed["palette"].items()
                              if colour(value) == colour(values[mode]))
                border_colours.append({"role": "palette_" + source, "label": values["label"]})
            for accent, values in {"default": {"label": "Default"}, **item.get("accents", {})}.items():
                if accent != "default" and mode not in values:
                    continue
                variants.append({"mode": mode, "accent": accent, "accentLabel": values["label"],
                    "flavour": seed["flavour"] + ("-" + accent if accent != "default" else ""),
                    "label": seed["label"], "borderColours": border_colours, "colours": palette({**seed,
                        "accent": values.get(mode, seed["accent"])}, mode)})
        result.append({"id": "hyprstack-" + item["id"], "name": item["name"], "custom": False,
                       "aliases": list(dict.fromkeys([item["id"], *item.get("aliases", [])])), "variants": variants})
    return result


def custom_theme(data: dict, identifier: str) -> dict:
    if not isinstance(data, dict):
        raise ValueError(_("Theme file must contain an object"))
    name = data.get("name")
    if not isinstance(name, str) or not name.strip() or len(name) > 80:
        raise ValueError(_("Choose a theme name (1–80 characters)"))
    modes = data.get("modes", data)
    if "colours" in data:
        modes = {data.get("mode", "dark"): data["colours"]}
    variants = []
    for mode in MODES:
        if mode in modes:
            values = modes[mode]
            values = values.get("colours", values) if isinstance(values, dict) else values
            variants.append({"mode": mode, "flavour": "default", "accent": "default", "accentLabel": "Default", "label": mode.capitalize(),
                             "colours": validate_colours(values, mode)})
    if not variants:
        raise ValueError(_("Add dark and/or light colours to the theme"))
    return {"id": identifier, "name": name.strip(), "custom": True, "aliases": [], "variants": variants}


def catalogue() -> dict:
    themes, errors = list(builtins()), []
    for path in sorted((CONFIG / "themes").glob("*.json")):
        try:
            identifier = path.stem if re.fullmatch(r"hyprstack-custom-[0-9a-f]{16}", path.stem) else (
                "hyprstack-custom-" + hashlib.sha256(path.name.encode()).hexdigest()[:16])
            themes.append(custom_theme(json.loads(path.read_text()), identifier))
        except (ValueError, OSError, TypeError) as error:
            errors.append(f"{path.name}: {error}")
    return {"themes": themes, "errors": errors}


def import_theme(data: dict) -> dict:
    # Names are display text, never paths. The content hash also avoids silently
    # replacing an existing theme when an import has the same display name.
    digest = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:16]
    identifier = "hyprstack-custom-" + digest
    theme = custom_theme(data, identifier)
    normalized = {"name": theme["name"], "modes": {v["mode"]: v["colours"] for v in theme["variants"]}}
    atomic_json(CONFIG / "themes" / (identifier + ".json"), normalized)
    install_scheme(theme)
    return theme


def install_scheme(theme: dict) -> None:
    for variant in theme["variants"]:
        path = DATA / "schemes" / theme["id"] / variant["flavour"] / (variant["mode"] + ".txt")
        path.parent.mkdir(parents=True, exist_ok=True)
        content = "".join(f"{key} {value}\n" for key, value in variant["colours"].items())
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(content)
                stream.close()
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)


def apply_theme(identifier: str, mode: str, accent: str | None = None, flavour: str | None = None) -> dict:
    theme = next((t for t in catalogue()["themes"] if t["id"] == identifier or identifier in t["aliases"]), None)
    if theme is None:
        raise ValueError(_("Unknown colour scheme"))
    current = read_current()
    variants = [v for v in theme["variants"] if v["mode"] == mode]
    if flavour is not None:
        variant = next((v for v in variants if v["flavour"] == flavour
                        and (accent is None or v["accent"] == accent)), None)
    else:
        if accent is None:
            previous = next((v for v in theme["variants"] if v["flavour"] == current.get("flavour")
                             and v["mode"] == current.get("mode")), None)
            same_theme = current.get("name") in [theme["id"], *theme["aliases"]]
            accent = (current.get("accent", previous["accent"] if previous else "default")
                      if same_theme else "default")
        variant = next((v for v in variants if v["accent"] == accent), None)
    if variant is None:
        raise ValueError(_('%1 has no %2 variant for the requested accent or flavour').replace('%1', str(theme['name'])).replace('%2', str(mode)))
    # Install only the selected accent's modes; unselected palettes remain read-only.
    install_scheme({**theme, "variants": [v for v in theme["variants"] if v["accent"] == variant["accent"]]})
    save_current({"name": theme["id"], "flavour": variant["flavour"], "mode": mode, "accent": variant["accent"],
                  "variant": current.get("variant", "tonalspot"), "colours": variant["colours"],
                  **({"paletteVersion": PALETTE_VERSION} if not theme["custom"] else {})})
    return {"name": theme["id"], "mode": mode, "accent": variant["accent"], "flavour": variant["flavour"]}


def save_current(scheme: dict) -> None:
    if scheme.get("mode") not in MODES:
        raise ValueError(_("Theme mode must be dark or light"))
    values = validate_colours(scheme["colours"], scheme["mode"])
    scheme = {**scheme, "colours": values}
    # The shell observes this file and applies native decoration colours live.
    # Application integration has its own journal and can be disabled separately.
    atomic_json(STATE / "scheme.json", scheme)
    config_root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = config_root / "hypr/scheme/current.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write("return {\n" + "".join(f'    {key} = "{value}",\n' for key, value in values.items()) + "}\n")
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    sync_applications()


def sync_applications() -> None:
    """A failed optional integration must not prevent changing the shell theme."""
    from theme_sync import sync_current
    try:
        result = sync_current()
        for error in result["errors"]:
            print("hyprstack theme sync: " + error, file=sys.stderr)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("hyprstack theme sync: " + str(error), file=sys.stderr)


def read_current() -> dict:
    try:
        result = json.loads((STATE / "scheme.json").read_text())
        return result if isinstance(result, dict) else {}
    except (OSError, ValueError):
        return {}


def refresh_current() -> dict:
    """Upgrade an installed builtin without changing the user's selection."""
    current = read_current()
    if current.get("paletteVersion") == PALETTE_VERSION:
        return {"updated": False}
    theme = next((t for t in builtins() if current.get("name") in [t["id"], *t["aliases"]]), None)
    if theme is None:
        return {"updated": False}
    variants = [v for v in theme["variants"] if v["mode"] == current.get("mode")]
    variant = next((v for v in variants if v["accent"] == current.get("accent")), None)
    if variant is None:
        variant = next((v for v in variants if v["flavour"] == current.get("flavour")), None)
    if variant is None:
        return {"updated": False}
    install_scheme({**theme, "variants": [v for v in theme["variants"] if v["accent"] == variant["accent"]]})
    save_current({**current, "accent": current.get("accent", variant["accent"]),
                  "colours": variant["colours"], "paletteVersion": PALETTE_VERSION})
    return {"updated": True}


def set_mode(mode: str) -> dict:
    if mode not in MODES:
        raise ValueError(_("Theme mode must be dark or light"))
    current = read_current()
    name = current.get("name", "catppuccin")
    theme = next((t for t in catalogue()["themes"] if name == t["id"] or name in t["aliases"]), None)
    if theme:
        return apply_theme(theme["id"], mode)
    if name == "dynamic":
        from hyprstack_cli import dynamic_scheme, wallpaper_path
        save_current(dynamic_scheme(wallpaper_path(), mode, current.get("variant", "tonalspot")))
        return {"name": name, "mode": mode}
    raise ValueError(_("The current scheme is unavailable; choose a scheme from the catalogue"))


def main() -> int:
    configure_argparse()
    parser = argparse.ArgumentParser(description=_("Manage Hyprstack colour schemes"))
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    sub.add_parser("refresh", help=_("Update the current builtin's palette, preserving its selection"))
    apply = sub.add_parser("apply")
    apply.add_argument("id")
    apply.add_argument("mode", choices=MODES)
    apply.add_argument("--accent")
    apply.add_argument("--flavour")
    mode = sub.add_parser("mode")
    mode.add_argument("mode", choices=MODES)
    imp = sub.add_parser("import")
    imp.add_argument("path")
    imp.add_argument("--mode", choices=MODES, default="dark", help=_("Mode for a Hyprstack .txt palette"))
    sub.add_parser("create", help=_("Read a theme JSON object from stdin"))
    args = parser.parse_args()
    try:
        if args.command == "list":
            result = catalogue()
        elif args.command == "refresh":
            result = refresh_current()
        elif args.command == "apply":
            result = apply_theme(args.id, args.mode, args.accent, args.flavour)
        elif args.command == "mode":
            result = set_mode(args.mode)
        elif args.command == "create":
            result = import_theme(json.load(sys.stdin))
        else:
            path = Path(args.path)
            if path.stat().st_size > 1024 * 1024:
                raise ValueError(_("Theme file is too large (maximum 1 MiB)"))
            if path.suffix.lower() == ".txt":
                colours = dict(line.split() for line in path.read_text().splitlines() if line.strip())
                data = {"name": path.stem, args.mode: colours}
            else:
                data = json.loads(path.read_text())
            result = import_theme(data)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (OSError, ValueError, TypeError, KeyError, ImportError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
