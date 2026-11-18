#!/bin/bash
# Compila e instala para el usuario actual, sin permisos de administrador:
#   ~/Applications/Margin.app  y  ~/.local/bin/margin (con `margen` y `espacio` como alias de los nombres anteriores)
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
app_src="${TMPDIR:-/tmp}/margin-local/Margin.app"
app_dst="$HOME/Applications/Margin.app"
bin_dst="$HOME/.local/bin/margin"
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
# Reemplaza solo una instalación anterior de esta misma app.
if [ -d "$app_dst" ]; then
  /usr/bin/plutil -extract CFBundleIdentifier raw "$app_dst/Contents/Info.plist" | grep -qx 'local.margin.mac' \
    || { echo "Ya existe otra app en $app_dst; no se sobrescribe." >&2; exit 1; }
  rm -rf "$app_dst"
fi
ditto "$app_src" "$app_dst"
codesign --verify --deep --strict "$app_dst"
install -m 0755 dist/margin "$bin_dst"
# Nombres anteriores: «Gestor Espacio» (hasta la 0.6) y «Margen» (0.7). Se retiran sus apps y sus comandos quedan
# como alias de `margin`.
for pair in "Gestor Espacio.app|local.gestorespacio.mac" "Margen.app|local.margen.mac"; do
  old_app="$HOME/Applications/${pair%%|*}"
  if [ -d "$old_app" ] && /usr/bin/plutil -extract CFBundleIdentifier raw "$old_app/Contents/Info.plist" 2>/dev/null | grep -qx "${pair##*|}"; then
    rm -rf "$old_app"
    echo "Retirada la app anterior: $old_app"
  fi
done
for alias in margen espacio; do
  if [ -e "$HOME/.local/bin/$alias" ] && [ ! -L "$HOME/.local/bin/$alias" ]; then rm -f "$HOME/.local/bin/$alias"; fi
  ln -sf margin "$HOME/.local/bin/$alias"
done
printf 'Instalado:\n  %s\n  %s (alias: margen, espacio)\n' "$app_dst" "$bin_dst"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Añade ~/.local/bin a tu PATH para usar 'margin' directamente." ;; esac
