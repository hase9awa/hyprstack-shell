#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$project_dir/distribution/configure.py" "$@"
