#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$("$ROOT_DIR/tools/ensure_godot.sh")" || exit 1
mkdir -p "$ROOT_DIR/build/linux"
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "Linux" "$ROOT_DIR/build/linux/MotivaBricks.x86_64"
STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  printf '\nLa exportacion no termino. Abre Godot, instala las plantillas de exportacion 4.7.1 y vuelve a ejecutar este archivo.\n' >&2
  exit $STATUS
fi
chmod +x "$ROOT_DIR/build/linux/MotivaBricks.x86_64" 2>/dev/null || true
printf '\nCreado: %s\n' "$ROOT_DIR/build/linux/MotivaBricks.x86_64"
