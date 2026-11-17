#!/bin/bash
# Compila e instala para el usuario actual, sin permisos de administrador:
#   ~/Applications/Gestor Espacio.app  y  ~/.local/bin/espacio
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
app_src="${TMPDIR:-/tmp}/gestor-espacio-local/Gestor Espacio.app"
app_dst="$HOME/Applications/Gestor Espacio.app"
bin_dst="$HOME/.local/bin/espacio"
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
# Reemplaza solo la instalación anterior de esta misma app.
if [ -d "$app_dst" ]; then
  /usr/bin/plutil -extract CFBundleIdentifier raw "$app_dst/Contents/Info.plist" | grep -qx 'local.gestorespacio.mac' \
    || { echo "Ya existe otra app en $app_dst; no se sobrescribe." >&2; exit 1; }
  rm -rf "$app_dst"
fi
ditto "$app_src" "$app_dst"
codesign --verify --deep --strict "$app_dst"
install -m 0755 dist/espacio "$bin_dst"
printf 'Instalado:\n  %s\n  %s\n' "$app_dst" "$bin_dst"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Añade ~/.local/bin a tu PATH para usar 'espacio' directamente." ;; esac
