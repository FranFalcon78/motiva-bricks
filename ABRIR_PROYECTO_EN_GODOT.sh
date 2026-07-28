#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$("$ROOT_DIR/tools/ensure_godot.sh")"
STATUS=$?
if [[ $STATUS -ne 0 || ! -x "$GODOT_BIN" ]]; then
  printf 'No se pudo localizar o descargar Godot.\n' >&2
  exit 1
fi
exec "$GODOT_BIN" --editor --path "$ROOT_DIR"
