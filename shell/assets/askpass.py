#!/usr/bin/env python3
"""Ask the shell for a passphrase on behalf of ssh or sudo.

Both tools run this program with the prompt as its argument and read the
answer from standard output. The answer travels over a socket in the runtime
directory, which belongs to this user alone, so the secret never appears in
a command line, in the environment or on disk.

Exiting non-zero without printing anything tells ssh and sudo that nobody
answered, and they fall back to asking on the terminal.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import socket
import sys


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not runtime or not re.fullmatch(r"[A-Za-z0-9_.-]+", signature):
        return None
    return Path(runtime) / ("hyprstack-askpass-" + signature + ".sock")


def ask(path, prompt):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(300)
        client.connect(str(path))
        client.sendall((json.dumps({"prompt": prompt}) + "\n").encode())
        answer = b""
        while not answer.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            answer += chunk
    return answer


def main():
    path = socket_path()
    if path is None:
        return 1

    prompt = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        answer = ask(path, prompt)
    except OSError:
        # No shell listening, or it went away mid-question.
        return 1

    try:
        reply = json.loads(answer.decode())
        if not reply.get("ok"):
            return 1
        secret = base64.b64decode(reply["secret"]).decode()
    except (ValueError, KeyError, UnicodeDecodeError):
        return 1

    sys.stdout.write(secret + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
