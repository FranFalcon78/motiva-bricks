#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$ROOT_DIR/pc_preview"
PORT="${MOTIVA_BRICKS_PORT:-8765}"
URL="http://127.0.0.1:${PORT}/"
LOG_FILE="${TMPDIR:-/tmp}/motiva-bricks-web-${USER:-user}.log"
PID_FILE="${TMPDIR:-/tmp}/motiva-bricks-web-${USER:-user}.pid"

open_browser() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 &
  elif command -v chromium >/dev/null 2>&1; then
    chromium "$URL" >/dev/null 2>&1 &
  elif command -v firefox >/dev/null 2>&1; then
    firefox "$URL" >/dev/null 2>&1 &
  else
    printf 'Abre esta dirección en tu navegador: %s\n' "$URL"
  fi
}

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    open_browser
    exit 0
  fi
fi

if command -v python3 >/dev/null 2>&1; then
  (cd "$WEB_DIR" && nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >"$LOG_FILE" 2>&1 & echo $! >"$PID_FILE")
elif command -v node >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && nohup node tools/web_server.mjs "$WEB_DIR" "$PORT" >"$LOG_FILE" 2>&1 & echo $! >"$PID_FILE")
else
  printf 'Se necesita Python 3 o Node.js para la vista web.\n' >&2
  exit 1
fi

for _try in $(seq 1 40); do
  if command -v curl >/dev/null 2>&1 && curl -fsS "$URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
open_browser
