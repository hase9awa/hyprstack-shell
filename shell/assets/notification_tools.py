#!/usr/bin/env python3
"""Keep notification images and screenshot actions alive across shell restarts."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlsplit


CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hyprstack/imagecache/notifs"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hyprstack/notifs.json"


def local_path(value: str) -> Path:
    if value.startswith("file:"):
        url = urlsplit(value)
        if url.netloc not in ("", "localhost"):
            raise ValueError("Only local screenshot files are supported")
        value = unquote(url.path)
    path = Path(value)
    if not path.is_absolute():
        raise ValueError("Screenshot path must be absolute")
    return path


def image_file(value: str) -> tuple[Path, bytes, str]:
    path = local_path(value)
    if not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("Image is missing or too large (maximum 64 MiB)")
    data = path.read_bytes()
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        kind = "png"
    elif data.startswith(b"\xff\xd8\xff"):
        kind = "jpeg"
    elif data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        kind = "webp"
    else:
        raise ValueError("Unsupported notification image; use PNG, JPEG or WebP")
    return path, data, kind


def cache_image(value: str) -> dict:
    path, data, kind = image_file(value)
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = CACHE / (hashlib.sha256(data).hexdigest() + "." + kind)
    if not target.exists():
        with tempfile.NamedTemporaryFile(dir=CACHE, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(data)
                stream.close()
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)
    return {"path": str(target), "original": str(path)}


def resolve_image(primary: str, fallback: str) -> tuple[Path, bytes, str]:
    for value in (primary, fallback):
        try:
            return image_file(value)
        except (OSError, ValueError):
            pass
    raise ValueError("This screenshot is no longer available")


def screenshot_action(action: str, primary: str, fallback: str) -> dict:
    path, data, kind = resolve_image(primary, fallback)
    if action == "copy":
        subprocess.run(["wl-copy", "--type", "image/" + kind], input=data, check=True)
    elif action in ("open", "preview"):
        if action == "open":
            subprocess.Popen(["xdg-open", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    elif action == "reveal":
        subprocess.Popen(["xdg-open", str(path.parent)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    else:
        pictures = os.environ.get("XDG_PICTURES_DIR")
        if not pictures:
            try:
                pictures = subprocess.check_output(["xdg-user-dir", "PICTURES"], text=True).strip()
            except (OSError, subprocess.CalledProcessError):
                pictures = str(Path.home() / "Pictures")
        directory = Path(os.environ.get("HYPRSTACK_SCREENSHOTS_DIR") or Path(pictures) / "Screenshots")
        directory.mkdir(parents=True, exist_ok=True)
        name = "Screenshot-" + datetime.now().strftime("%Y-%m-%d_%H-%M-%S-%f") + "." + kind
        path = directory / name
        with path.open("xb") as stream:
            stream.write(data)
        path.chmod(0o600)
    return {"path": str(path), "action": action}


def prune_cache() -> dict:
    # Never delete original screenshots, files outside our cache, or recently
    # created images that may not have reached the debounced history write yet.
    data = json.loads(STATE.read_text())
    records = data if isinstance(data, list) else data["notifications"]
    keep = {str(local_path(n["image"])) for n in records if n.get("image", "").startswith(("/", "file:"))}
    removed = 0
    for path in CACHE.glob("*"):
        if (not path.is_symlink() and path.is_file() and str(path) not in keep
                and re.fullmatch(r"[0-9a-f]{16,64}\.(png|jpeg|webp)", path.name)
                and time.time() - path.stat().st_mtime > 300):
            path.unlink()
            removed += 1
    return {"removed": removed}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    cache = sub.add_parser("cache")
    cache.add_argument("path")
    action = sub.add_parser("action")
    action.add_argument("action", choices=("open", "preview", "copy", "save", "reveal"))
    action.add_argument("path")
    action.add_argument("fallback")
    sub.add_parser("prune")
    args = parser.parse_args()
    try:
        if args.command == "cache":
            result = cache_image(args.path)
        elif args.command == "action":
            result = screenshot_action(args.action, args.path, args.fallback)
        else:
            result = prune_cache()
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
