#!/usr/bin/env python3
"""Read-only checks for a Hyprstack desktop installation."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from i18n import _, configure_argparse


def capture(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def checks():
    home = Path.home()
    data = Path(os.environ.get("HYPRSTACK_DATA_DIR", Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")) / "hyprstack"))
    version_text = capture(["Hyprland", "--version-json"])
    try: version = json.loads(version_text or "{}")
    except ValueError: version = {}
    result = [{"check": "Hyprland 0.56.2", "ok": version.get("version") == "0.56.2", "value": version.get("version", "missing")}]
    qs = capture(["qs", "--version"]) or ""
    match = re.search(r"Quickshell (\d+)\.(\d+)\.(\d+)", qs)
    result.append({"check": "Quickshell >= 0.3.1", "ok": bool(match and tuple(map(int, match.groups())) >= (0, 3, 1)), "value": qs or "missing"})
    for name in ("wl-paste", "cliphist", "wpctl", "xdg-open"):
        result.append({"check": name, "ok": bool(shutil.which(name)), "value": shutil.which(name) or "missing"})
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    try:
        path = config / "hyprstack/shell.json"
        prefs = json.loads(path.read_text()) if path.exists() else {}
        terminal = prefs.get("general", {}).get("apps", {}).get("terminal", ["kitty"])
        if not isinstance(terminal, list) or not terminal or not all(isinstance(arg, str) for arg in terminal):
            raise ValueError("general.apps.terminal must be a non-empty array of strings")
        result.append({"check": "Configured terminal", "ok": bool(shutil.which(terminal[0])), "value": shlex.join(terminal)})
    except (OSError, ValueError, AttributeError) as error:
        result.append({"check": "Configured terminal", "ok": False, "value": str(error)})
    for name in ("shell/shell.qml", "qml/Hyprstack/qmldir", "qml/M3Shapes/qmldir", "native/hyprstack-bars.so"):
        result.append({"check": name, "ok": (data / name).is_file(), "value": str(data / name)})
    pam = os.environ.get("HYPRSTACK_PAM_SERVICE", "hyprlock")
    result.append({"check": "PAM lock service", "ok": bool(re.fullmatch(r"[A-Za-z0-9_.-]+", pam) and Path("/etc/pam.d", pam).is_file()), "value": pam})
    try:
        native = json.loads((data / "native/native-version.json").read_text())
    except (OSError, ValueError): native = {}
    result.append({"check": "Native plugin ABI", "ok": bool(version.get("abiHash") and native.get("abiHash") == version["abiHash"]), "value": native.get("abiHash", "missing")})
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        text = capture(["hyprctl", "-j", "version"])
        try: running = json.loads(text or "{}")
        except ValueError: running = {}
        result.append({"check": "Installed/running Hyprland ABI", "ok": bool(version.get("abiHash") and running.get("abiHash") == version["abiHash"]), "value": running.get("abiHash", "missing")})
        errors = capture(["hyprctl", "configerrors"])
        result.append({"check": "Hyprland configuration", "ok": errors in ("", "ok"), "value": errors or ""})
    return result


def main():
    configure_argparse()
    parser = argparse.ArgumentParser(description=_("Check the Hyprstack installation"))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results = checks()
    if args.json: print(json.dumps(results, indent=2))
    else:
        for row in results:
            print((_("OK") if row["ok"] else _("FAIL")) + "  " + _(row["check"]) + ": "
                + (_("missing") if row["value"] == "missing" else row["value"]))
    return 0 if all(row["ok"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
