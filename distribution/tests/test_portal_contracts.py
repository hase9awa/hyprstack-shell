#!/usr/bin/env python3
"""Exercise portal replies and NetworkManager requests on a disposable D-Bus.

Run with the CMake build directory as the first argument.
"""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile


def main():
    if "--private-bus" not in sys.argv:
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, sys.argv[1], "--private-bus"], check=True)
        return
    os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
    root = Path(__file__).resolve().parents[2]
    build = Path(sys.argv[1]).resolve() / "shell/plugin/src/Hyprstack"
    source = Path(__file__).with_name("portal_contracts.cpp")
    includes = ["-I" + str(root / "shell/plugin/src/Hyprstack" / name) for name in ["Services", "Portals"]]
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "Qt6Core", "Qt6Qml", "Qt6DBus"], text=True))
    with tempfile.TemporaryDirectory(prefix="hs-portal-test-") as temp:
        subprocess.run(["/usr/lib/qt6/moc", *includes, *[f for f in flags if f.startswith(("-I", "-D"))],
                        str(source), "-o", temp + "/portal_contracts.moc"], check=True)
        libraries = [build / name / ("libhyprstack-" + name.lower() + ".so") for name in ["Services", "Portals"]]
        subprocess.run(["c++", "-std=c++20", "-fPIC", "-I" + temp, *includes,
                        str(source), *map(str, libraries), *["-Wl,-rpath," + str(p.parent) for p in libraries],
                        *flags, "-o", temp + "/contracts"], check=True)
        subprocess.run([temp + "/contracts"], check=True)


if __name__ == "__main__":
    main()
