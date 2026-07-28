#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$("$ROOT_DIR/tools/ensure_godot.sh")" || exit 1
mkdir -p "$ROOT_DIR/build/android"
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-debug "Android Debug" "$ROOT_DIR/build/android/MotivaBricks-debug.apk"
STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  printf '\nLa exportacion Android necesita las plantillas Godot 4.7.1, Java y Android SDK configurados. Consulta docs/EXPORTACION_ANDROID.md.\n' >&2
  exit $STATUS
fi
printf '\nCreado: %s\n' "$ROOT_DIR/build/android/MotivaBricks-debug.apk"
