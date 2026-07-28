#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$("$ROOT_DIR/tools/ensure_godot.sh")"
STATUS=$?
if [[ $STATUS -ne 0 || ! -x "$GODOT_BIN" ]]; then
  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    if zenity --question --title="Motiva Bricks" --width=540 --text="Godot no esta disponible. Abrir la version web de compatibilidad para jugar ahora?" 2>/dev/null; then
      exec "$ROOT_DIR/PROBAR_VERSION_WEB.sh"
    fi
  fi
  printf '\nNo se pudo iniciar Godot. Puedes ejecutar: %s\n' "$ROOT_DIR/PROBAR_VERSION_WEB.sh" >&2
  read -r -p "Pulsa Intro para cerrar..." _ 2>/dev/null || true
  exit 1
fi
exec "$GODOT_BIN" --path "$ROOT_DIR"
