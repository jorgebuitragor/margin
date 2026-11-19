#!/bin/bash
# Publica una versión de Margin en GitHub Releases para que las copias instaladas se actualicen solas (Sparkle).
#
#   1. Sube la versión en VERSION y describe los cambios en CHANGELOG.md («## <versión>»).
#   2. Haz commit y push de main.
#   3. bash scripts/release.sh
#
# Todo pasa en este Mac: la app se firma con «Margin Local» y la actualización con la clave EdDSA de Sparkle, que vive
# en el llavero (la crea este script la primera vez y guarda la pública en Resources/sparkle-clave-publica.txt).
# Ninguna clave sale del Mac ni se guarda en GitHub. La release lleva el ZIP de la app y appcast.xml, que es lo que
# lee Sparkle en https://github.com/jorgebuitragor/margin/releases/latest/download/appcast.xml, y Margin.dmg para
# descargarla a mano (…/releases/latest/download/Margin.dmg).
set -euo pipefail
cd "$(dirname "$0")/.."
repo="jorgebuitragor/margin"
version="$(tr -d '[:space:]' < VERSION)"
tag="v$version"

# Comprobaciones antes de publicar nada.
[ "$(git branch --show-current)" = "main" ] || { echo "Publica desde main." >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Hay cambios sin commit." >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main no coincide con origin/main: haz push primero." >&2; exit 1; }
gh release view "$tag" -R "$repo" >/dev/null 2>&1 && { echo "La release $tag ya existe: sube la versión en VERSION." >&2; exit 1; }
notes="$(awk -v v="## $version" '$0 == v {found=1; next} /^## / && found {exit} found' CHANGELOG.md)"
[ -n "$notes" ] || { echo "Falta la sección «## $version» en CHANGELOG.md." >&2; exit 1; }

# Herramientas de Sparkle (generate_keys, sign_update): vienen con la dependencia de Swift, en la misma versión.
scratch="${TMPDIR:-/tmp}/margin-build"
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/margin-clang-cache" swift package resolve --disable-sandbox --scratch-path "$scratch" >/dev/null
tools="$scratch/artifacts/sparkle/Sparkle"
[ -x "$tools/bin/sign_update" ] || { echo "No se encontraron las herramientas de Sparkle en $tools." >&2; exit 1; }

# Clave de las actualizaciones: se crea una sola vez. Si se pierde, las copias instaladas no aceptarán más versiones.
if [ ! -s Resources/sparkle-clave-publica.txt ]; then
  "$tools/bin/generate_keys" >/dev/null
  "$tools/bin/generate_keys" -p > Resources/sparkle-clave-publica.txt
  echo "Clave pública creada en Resources/sparkle-clave-publica.txt: haz commit y push, y vuelve a ejecutar este script." >&2
  exit 1
fi

bash scripts/build-app.sh
zip="dist/Margin-$version.zip"
mv dist/Margin.zip "$zip"
# Para descargar e instalar a mano: nombre fijo, así …/releases/latest/download/Margin.dmg es siempre la última.
bash scripts/make-dmg.sh "${TMPDIR:-/tmp}/margin-local/Margin.app" dist/Margin.dmg
signature="$("$tools/bin/sign_update" "$zip")"   # sparkle:edSignature="…" length="…"
build="$(git rev-list --count HEAD)"
html="$(printf '%s\n' "$notes" | sed -E 's/^- (.*)$/<li>\1<\/li>/' | grep '<li>' || true)"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Margin</title>
    <link>https://github.com/$repo</link>
    <item>
      <title>Margin $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$html</ul>]]></description>
      <enclosure url="https://github.com/$repo/releases/download/$tag/Margin-$version.zip" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML
gh release create "$tag" -R "$repo" --title "Margin $version" --notes "$notes" --target main "$zip" dist/appcast.xml dist/Margin.dmg
echo "Publicada $tag. Las copias instaladas la verán en su próxima comprobación (o con Margin › Buscar actualizaciones…)."
