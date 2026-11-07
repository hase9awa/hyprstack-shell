#!/usr/bin/env python3
"""Test the real HyprExtras IPC reader and QML helpers against a mock compositor.

Usage: python3 distribution/tests/test_client_snapshot.py /path/to/cmake-build
The build must include the plugin module. No running session is modified.
"""
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    build = Path(sys.argv[1]).resolve()
    library = build / "shell/plugin/src/Hyprstack/Services/libhyprstack-services.so"
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "Qt6Core", "Qt6Network", "Qt6Qml"], text=True))
    with tempfile.TemporaryDirectory(prefix="hyprstack-client-test-") as temp:
        executable = Path(temp) / "client-snapshot"
        subprocess.run(["c++", "-std=c++20", "-fPIC",
                        "-I" + str(root / "shell/plugin/src/Hyprstack/Services"),
                        str(Path(__file__).with_name("client_snapshot.cpp")),
                        str(library), "-Wl,-rpath," + str(library.parent),
                        *flags, "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(root / "shell/services/ClientSnapshot.js")], check=True)


if __name__ == "__main__":
    main()
