#!/bin/bash
# Compila e instala para el usuario actual, sin permisos de administrador:
#   ~/Applications/Margen.app  y  ~/.local/bin/margen (con `espacio` como alias del nombre anterior)
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
app_src="${TMPDIR:-/tmp}/margen-local/Margen.app"
app_dst="$HOME/Applications/Margen.app"
bin_dst="$HOME/.local/bin/margen"
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
# Reemplaza solo una instalación anterior de esta misma app.
if [ -d "$app_dst" ]; then
  /usr/bin/plutil -extract CFBundleIdentifier raw "$app_dst/Contents/Info.plist" | grep -qx 'local.margen.mac' \
    || { echo "Ya existe otra app en $app_dst; no se sobrescribe." >&2; exit 1; }
  rm -rf "$app_dst"
fi
ditto "$app_src" "$app_dst"
codesign --verify --deep --strict "$app_dst"
install -m 0755 dist/margen "$bin_dst"
# Nombre anterior (hasta la 0.6): la app «Gestor Espacio» se retira y `espacio` queda como alias de `margen`.
old_app="$HOME/Applications/Gestor Espacio.app"
if [ -d "$old_app" ] && /usr/bin/plutil -extract CFBundleIdentifier raw "$old_app/Contents/Info.plist" 2>/dev/null | grep -qx 'local.gestorespacio.mac'; then
  rm -rf "$old_app"
  echo "Retirada la app anterior: $old_app"
fi
ln -sf margen "$HOME/.local/bin/espacio"
printf 'Instalado:\n  %s\n  %s (alias: espacio)\n' "$app_dst" "$bin_dst"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Añade ~/.local/bin a tu PATH para usar 'margen' directamente." ;; esac
