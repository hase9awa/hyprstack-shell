#!/usr/bin/env python3
"""Ask the shell what an application may capture of the screen.

The desktop portal runs this program when an application asks to share the
screen and reads the choice from its standard output. The windows it is
willing to hand over arrive in XDPH_WINDOW_SHARING_LIST; the choice travels
over a socket in the runtime directory, which belongs to this user alone, so
nothing else on the machine can be asked what to share or read the answer.

Printing nothing is how the portal is told that nobody chose anything, which
is what a cancelled dialog and a shell that is not listening both amount to.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import socket
import sys

# Each window arrives as its handle, class, title and address, every field
# closed by a marker of its own rather than separated from the next.
WINDOW_FIELDS = (("handle", "[HC>]"), ("class", "[HT>]"), ("title", "[HE>]"), ("address", "[HA>]"))

# What the portal understands: a whole output, one of the windows it offered,
# or a rectangle of an output.
SELECTIONS = re.compile(r"screen:[^\s/]+|window:[0-9]+|region:[^\s/@]+@-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+")


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not runtime or not re.fullmatch(r"[A-Za-z0-9_.-]+", signature):
        return None
    return Path(runtime) / ("hyprstack-share-picker-" + signature + ".sock")


def windows(listing):
    """Read the portal's window list; a truncated entry ends the list."""
    result = []
    while listing:
        window = {}
        for field, marker in WINDOW_FIELDS:
            value, found, listing = listing.partition(marker)
            if not found:
                return result
            window[field] = value.strip()
        if window["handle"].isdigit():
            result.append(window)
    return result


def ask(path, question):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        # The choice is the user's to make, so the only deadline is the one
        # the portal itself keeps on this program.
        client.settimeout(300)
        client.connect(str(path))
        client.sendall((json.dumps(question) + "\n").encode())
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

    question = {
        "allowToken": "--allow-token" in sys.argv[1:],
        "windows": windows(os.environ.get("XDPH_WINDOW_SHARING_LIST", "")),
    }

    try:
        answer = ask(path, question)
    except OSError:
        # No shell listening, or it went away while the dialog was open.
        return 1

    try:
        reply = json.loads(answer.decode())
        if not reply.get("ok"):
            return 1
        selection = str(reply["selection"])
    except (ValueError, KeyError, UnicodeDecodeError):
        return 1

    if not SELECTIONS.fullmatch(selection):
        return 1

    # The portal reads the flags ahead of the slash and drops the character
    # behind an output name, so both the slash and the newline belong here.
    sys.stdout.write("[SELECTION]" + ("r" if reply.get("token") else "") + "/" + selection + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
