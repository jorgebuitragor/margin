#!/bin/bash
# Crea la imagen de disco para descargar Margin: dentro, Margin.app y un acceso a la carpeta Aplicaciones para arrastrarla.
#
#   bash scripts/make-dmg.sh <Margin.app> <salida.dmg>
#
# La imagen se firma con «Margin Local» (o ad hoc si no existe). Las actualizaciones automáticas siguen usando el ZIP;
# el .dmg es solo para la primera instalación.
set -euo pipefail
app="${1:?Uso: make-dmg.sh <Margin.app> <salida.dmg>}"
out="${2:?Uso: make-dmg.sh <Margin.app> <salida.dmg>}"
[ -d "$app/Contents" ] || { echo "No es una app: $app" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Margin.app"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -quiet -volname "Margin" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$out"
if security find-certificate -c "Margin Local" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  codesign --force --sign "Margin Local" "$out"
else
  codesign --force --sign - "$out"
fi
hdiutil verify -quiet "$out"
echo "Imagen creada: $out"
