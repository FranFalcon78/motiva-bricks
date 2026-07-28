#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$ROOT_DIR/tools/static_project_check.py" || exit 1
python3 "$ROOT_DIR/tools/validate_levels.py" || exit 1
GODOT_BIN="$("$ROOT_DIR/tools/ensure_godot.sh")" || exit 1
"$GODOT_BIN" --headless --path "$ROOT_DIR" --script res://tools/godot_smoke_test.gd
