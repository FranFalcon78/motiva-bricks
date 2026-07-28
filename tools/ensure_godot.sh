#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/runtime"
GODOT_VERSION="4.7.1"
GODOT_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
LOCAL_GODOT="$RUNTIME_DIR/$GODOT_NAME"
ZIP_PATH="$RUNTIME_DIR/${GODOT_NAME}.zip"
PART_PATH="$ZIP_PATH.part"
LOG_PATH="$RUNTIME_DIR/godot-download.log"
OFFICIAL_URL="https://downloads.godotengine.org/?flavor=stable&platform=linux.64&slug=linux.x86_64.zip&version=${GODOT_VERSION}"
GITHUB_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${GODOT_NAME}.zip"

show_error() {
  local message="$1"
  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    zenity --error --title="Motiva Bricks" --width=560 --text="$message" 2>/dev/null || true
  else
    printf '\nERROR: %s\n' "$message" >&2
  fi
}

show_info() {
  local message="$1"
  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    zenity --info --title="Motiva Bricks" --width=560 --text="$message" 2>/dev/null || true
  else
    printf '%s\n' "$message" >&2
  fi
}

find_installed_godot() {
  local candidate path version
  for candidate in godot4 godot godot-engine; do
    if command -v "$candidate" >/dev/null 2>&1; then
      path="$(command -v "$candidate")"
      version="$("$path" --version 2>/dev/null | head -n 1 || true)"
      case "$version" in
        4.7.*|4.8.*|4.9.*) printf '%s\n' "$path"; return 0 ;;
      esac
    fi
  done
  return 1
}

download_file() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --retry 2 --retry-delay 1 \
      --connect-timeout 20 --output "$PART_PATH" "$url"
  else
    wget --quiet --timeout=20 --tries=3 --output-document="$PART_PATH" "$url"
  fi
}

download_with_progress() {
  local url="$1"
  local label="$2"
  rm -f "$PART_PATH"
  : > "$LOG_PATH"

  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    (download_file "$url" >"$LOG_PATH" 2>&1) &
    local download_pid=$!
    (
      while kill -0 "$download_pid" 2>/dev/null; do
        printf '# %s\n' "$label"
        sleep 0.35
      done
    ) | zenity --progress --title="Motiva Bricks" --text="$label" --pulsate \
        --auto-close --no-cancel --width=560 2>/dev/null || true
    wait "$download_pid"
    return $?
  fi

  printf '%s\n' "$label" >&2
  download_file "$url" >"$LOG_PATH" 2>&1
}

verify_zip() {
  if command -v unzip >/dev/null 2>&1; then
    unzip -tqq "$PART_PATH" >/dev/null 2>&1
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$PART_PATH" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    bad = archive.testzip()
    raise SystemExit(1 if bad else 0)
PY
    return $?
  fi
  return 1
}

extract_zip() {
  if command -v unzip >/dev/null 2>&1; then
    unzip -o "$PART_PATH" -d "$RUNTIME_DIR" >/dev/null
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$PART_PATH" "$RUNTIME_DIR" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
PY
    return $?
  fi
  return 1
}

if [[ -x "$LOCAL_GODOT" ]]; then
  printf '%s\n' "$LOCAL_GODOT"
  exit 0
fi

if INSTALLED_GODOT="$(find_installed_godot)"; then
  printf '%s\n' "$INSTALLED_GODOT"
  exit 0
fi

mkdir -p "$RUNTIME_DIR"

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  show_error "No se encontro Godot, curl ni wget. Ejecuta PROBAR_VERSION_WEB.sh o instala Godot 4.7.1."
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  show_error "Se necesita unzip o Python 3 para preparar Godot. Ejecuta PROBAR_VERSION_WEB.sh mientras tanto."
  exit 1
fi

show_info "Primer inicio: Motiva Bricks descargara Godot ${GODOT_VERSION} Standard desde el servidor oficial (aprox. 76 MB). Se guardara dentro de runtime y no volvera a descargarse en los siguientes inicios."

DOWNLOAD_OK=0
if download_with_progress "$OFFICIAL_URL" "Descargando Godot ${GODOT_VERSION} desde el servidor oficial..."; then
  DOWNLOAD_OK=1
else
  rm -f "$PART_PATH"
  if download_with_progress "$GITHUB_URL" "Reintentando la descarga desde el repositorio oficial..."; then
    DOWNLOAD_OK=1
  fi
fi

if [[ "$DOWNLOAD_OK" -ne 1 || ! -s "$PART_PATH" ]]; then
  rm -f "$PART_PATH"
  show_error "No se pudo descargar Godot. Comprueba la conexion o abre PROBAR_VERSION_WEB.sh. El detalle tecnico queda en runtime/godot-download.log."
  exit 1
fi

if ! verify_zip; then
  rm -f "$PART_PATH"
  show_error "La descarga de Godot esta incompleta o no es un ZIP valido. Vuelve a iniciar Motiva Bricks para reintentarlo."
  exit 1
fi

if ! extract_zip; then
  rm -f "$PART_PATH"
  show_error "Godot se descargo, pero no se pudo descomprimir."
  exit 1
fi

mv "$PART_PATH" "$ZIP_PATH"
chmod +x "$LOCAL_GODOT" 2>/dev/null || true
rm -f "$ZIP_PATH"

if [[ ! -x "$LOCAL_GODOT" ]]; then
  show_error "Godot se descargo, pero no aparecio el ejecutable esperado: $GODOT_NAME"
  exit 1
fi

printf '%s\n' "$LOCAL_GODOT"
