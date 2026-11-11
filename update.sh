#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
project_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi
# Keep the source-build and rollback interface for maintenance and development.
for argument in "$@"; do
    case "$argument" in
        --no-pull|--dry-run|--rollback)
            if [[ -z "$project_dir" || ! -f "$project_dir/distribution/update.py" ]]; then
                printf 'Эти параметры требуют локальных исходников Hyprstack.\n' >&2
                exit 1
            fi
            exec python3 "$project_dir/distribution/update.py" "$@"
            ;;
    esac
done
if [[ -n "$project_dir" && -f "$project_dir/distribution/updates.py" ]]; then
    exec python3 "$project_dir/distribution/updates.py" "$@"
fi
if command -v hyprstack-update >/dev/null 2>&1; then
    exec hyprstack-update "$@"
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf 'Для обновления Hyprstack требуется python3.\n' >&2
    exit 1
fi
# Bootstrap older installations from the published release's updater. Cache the
# helpers so the detached installer can still read them after the terminal exits.
exec python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen

repository = "hase9awa/hyprstack-shell"
def download(url, limit):
    with urlopen(Request(url, headers={"User-Agent": "Hyprstack-Updater"}), timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Ответ сервера слишком большой")
    return data

try:
    if os.geteuid() == 0:
        raise ValueError("Запускайте обновление обычным пользователем, без sudo")
    release = json.loads(download("https://api.github.com/repos/" + repository + "/releases/latest", 1024 * 1024))
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v?\d+\.\d+\.\d+", tag):
        raise ValueError("Не найден стабильный релиз Hyprstack")
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "hyprstack-bootstrap" / tag
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in ("updates.py", "update.py", "update_transaction.py", "check_headers.py"):
        data = download("https://raw.githubusercontent.com/" + repository + "/" + tag + "/distribution/" + name, 2 * 1024 * 1024)
        fd, temporary = tempfile.mkstemp(dir=cache)
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
            os.replace(temporary, cache / name)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
    raise SystemExit(subprocess.call([sys.executable, str(cache / "updates.py"), *sys.argv[1:]]))
except (OSError, ValueError) as error:
    print("Не удалось запустить обновление:", error, file=sys.stderr)
    raise SystemExit(1)
PY
