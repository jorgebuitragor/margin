#!/bin/bash
# Crea una carpeta personal ficticia para las capturas del README (y para probar la app sin datos reales).
#
#   bash scripts/demo-home.sh /private/tmp/margin-demo
#   MARGIN_HOME=/private/tmp/margin-demo MARGIN_CAPTURAS=1 open -n ~/Applications/Margin.app
#
# Tiene proyectos inactivos con node_modules, cachés de apps, Xcode, Gradle, npm y nvm, instaladores viejos en
# Descargas, una copia del iPhone, la Papelera, apps de ejemplo con sus restos y restos de apps ya borradas.
# Los archivos grandes son clones APFS de tres «semillas» (cp -c): Margin ve los tamaños reales de cada archivo
# (varios GB en total), pero en disco solo ocupan las semillas, unos 340 MB, en <carpeta>.semillas. Borrar las
# dos carpetas lo deshace todo.
set -euo pipefail
home="${1:?Uso: demo-home.sh <carpeta nueva>}"
[[ -e "$home" || -e "$home.semillas" ]] && { echo "Ya existe $home o $home.semillas; bórralas antes o elige otra." >&2; exit 1; }
mkdir -p "$home"
home="$(cd "$home" && pwd -P)"
# Las semillas van al lado, no dentro: así no aparecen en el mapa de la carpeta.
seeds="$home.semillas"
mkdir -p "$seeds"
head -c $((16 * 1024 * 1024)) /dev/urandom > "$seeds/16"
head -c $((64 * 1024 * 1024)) /dev/urandom > "$seeds/64"
head -c $((256 * 1024 * 1024)) /dev/urandom > "$seeds/256"

# fill <carpeta> <MB>: llena la carpeta con clones hasta ese tamaño (múltiplos de 16 MB).
fill() {
  local dir="$1" left="$2" n=0
  mkdir -p "$dir"
  for size in 256 64 16; do
    while (( left >= size )); do
      cp -c "$seeds/$size" "$dir/parte-$n.bin"
      n=$((n + 1)); left=$((left - size))
    done
  done
}
# file <ruta> <MB>: un solo archivo clonado de la semilla de 16, 64 o 256 MB.
file() { mkdir -p "$(dirname "$1")"; cp -c "$seeds/$2" "$1"; }
# age <ruta> <días>: fecha de modificación antigua en todo lo que hay dentro.
age() { local stamp; stamp="$(date -v-"$2"d +%Y%m%d%H%M)"; find "$1" -exec touch -h -t "$stamp" {} +; }
# project <carpeta> <días sin commits>
project() {
  local dir="$1" days="$2" when
  when="$(date -v-"$days"d +%Y-%m-%dT10:00:00)"
  git -C "$dir" init -q
  git -C "$dir" add -A -- ':!node_modules' ':!.next' ':!.expo' ':!.build' ':!.venv' 2>/dev/null || true
  GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$dir" -c user.name=Ana -c user.email=ana@example.com commit -qm "Primera versión" --allow-empty
  age "$dir" "$days"
}
# Generador de iconos de ejemplo (símbolo SF sobre un degradado), compilado una vez.
icon_tool="$seeds/demo-icon"
swiftc -O "$(dirname "$0")/demo-icon.swift" -o "$icon_tool" 2>/dev/null
# app <Nombre> <identificador> <MB> <días desde el último uso> <símbolo> <r> <g> <b>: app de ejemplo en ~/Applications.
app() {
  local dir="$home/Applications/$1.app/Contents"
  mkdir -p "$dir/MacOS" "$dir/Resources"
  # Juego completo de tamaños (16 a 1024 px): con uno solo, macOS lo dibuja desvaído en las listas.
  local set="$seeds/icono.iconset"
  rm -rf "$set" && mkdir -p "$set"
  "$icon_tool" "$5" "$6" "$7" "$8" "$seeds/icono.png"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$seeds/icono.png" --out "$set/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$seeds/icono.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$dir/Resources/AppIcon.icns"
  cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleName</key><string>$1</string>
<key>CFBundleExecutable</key><string>$1</string>
<key>CFBundleShortVersionString</key><string>2.4</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
  fill "$dir/MacOS/datos" "$3"
  # Un ejecutable mínimo: sin él macOS trata el paquete como una app rota y dibuja su icono apagado.
  printf '#!/bin/sh\nexit 0\n' > "$dir/MacOS/$1" && chmod +x "$dir/MacOS/$1"
  # Último uso: fuera de las carpetas que indexa Spotlight, kMDItemLastUsedDate es la fecha de modificación del .app.
  touch -h -t "$(date -v-"$4"d -v-1H +%Y%m%d%H%M)" "$home/Applications/$1.app"
}

# Proyectos: tres inactivos (se proponen) y uno activo (no se toca).
mkdir -p "$home/Developer/tienda-web" "$home/Developer/app-movil" "$home/Developer/cli-swift" "$home/Developer/api-pagos"
echo '{"name":"tienda-web","scripts":{"dev":"next dev"}}' > "$home/Developer/tienda-web/package.json"
fill "$home/Developer/tienda-web/node_modules" 1248
fill "$home/Developer/tienda-web/.next" 320
project "$home/Developer/tienda-web" 140
echo '{"name":"app-movil","main":"expo-router/entry"}' > "$home/Developer/app-movil/package.json"
fill "$home/Developer/app-movil/node_modules" 896
fill "$home/Developer/app-movil/.expo" 64
project "$home/Developer/app-movil" 75
printf '// swift-tools-version:6.0\nimport PackageDescription\nlet package = Package(name: "cli")\n' > "$home/Developer/cli-swift/Package.swift"
fill "$home/Developer/cli-swift/.build" 592
project "$home/Developer/cli-swift" 210
echo '{"name":"api-pagos"}' > "$home/Developer/api-pagos/package.json"
fill "$home/Developer/api-pagos/node_modules" 432
project "$home/Developer/api-pagos" 0

# Herramientas de desarrollo.
fill "$home/Library/Developer/Xcode/DerivedData/Tienda-bxkqzjv" 2048
fill "$home/Library/Developer/Xcode/DerivedData/Widgets-aamfwe" 768
fill "$home/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.2 (21C62)" 1536
age "$home/Library/Developer/Xcode" 160
fill "$home/.gradle/caches/modules-2" 1280
fill "$home/.gradle/wrapper/dists/gradle-7.6-bin" 128
fill "$home/.gradle/wrapper/dists/gradle-8.10-bin" 144
age "$home/.gradle/wrapper/dists/gradle-7.6-bin" 300
fill "$home/.npm/_cacache" 704
for v in v18.20.4 v20.18.0 v22.11.0; do fill "$home/.nvm/versions/node/$v/lib" 96; mkdir -p "$home/.nvm/versions/node/$v/bin"; done
mkdir -p "$home/.nvm/alias" && echo "v22.11.0" > "$home/.nvm/alias/default"

# Cachés de apps y registros.
fill "$home/Library/Caches/Google" 720
fill "$home/Library/Caches/JetBrains" 896
fill "$home/Library/Caches/com.ejemplo.lienzo" 352
fill "$home/Library/Caches/com.ejemplo.radio" 144
fill "$home/Library/Logs/Lienzo" 112
fill "$home/Library/Logs/DiagnosticReports" 32
age "$home/Library/Logs" 40

# Descargas: instaladores viejos (para revisar) y archivos personales.
file "$home/Downloads/Figma-Installer.dmg" 256
file "$home/Downloads/Controlador-Impresora.pkg" 64
cp -c "$seeds/256" "$home/Downloads/Xcode_16.1.xip"
file "$home/Downloads/fotos-viaje.zip" 256
age "$home/Downloads" 95
file "$home/Downloads/factura-noviembre.pdf" 16

# Documentos personales (Margin nunca los propone).
fill "$home/Documents/Fotos 2025" 2304
fill "$home/Documents/Videos familia" 3072
fill "$home/Documents/Trabajo/Presentaciones" 448
file "$home/Documents/Trabajo/Informe anual.pdf" 16
fill "$home/Music/Biblioteca" 1536
fill "$home/Pictures/Capturas" 320

# Copia del iPhone y Papelera.
fill "$home/Library/Application Support/MobileSync/Backup/00008110-001A2B3C4D5E6F70" 4096
age "$home/Library/Application Support/MobileSync" 200
fill "$home/.Trash" 1152

# Apps de ejemplo con sus restos.
app "Lienzo" "com.ejemplo.lienzo" 416 0 paintbrush.pointed.fill 0.55 0.36 0.95
app "Fotón" "com.ejemplo.foton" 640 3 camera.aperture 0.20 0.50 0.95
app "Video Express" "com.ejemplo.video" 1024 12 film.stack 0.92 0.30 0.30
app "Contable" "com.ejemplo.contable" 160 1 chart.bar.xaxis 0.18 0.66 0.42
app "Mapas Mentales" "com.ejemplo.mapas" 208 45 brain.head.profile 0.93 0.36 0.62
app "Radio" "com.ejemplo.radio" 96 130 radio.fill 0.97 0.55 0.18
app "Notas Rápidas" "com.ejemplo.notas" 64 2 note.text 0.95 0.75 0.15
app "Traductor" "com.ejemplo.traductor" 112 220 character.bubble.fill 0.10 0.65 0.72
fill "$home/Library/Application Support/com.ejemplo.lienzo" 512
fill "$home/Library/Application Support/com.ejemplo.mapas" 64
mkdir -p "$home/Library/Preferences"
fill "$home/Library/Application Support/com.ejemplo.video" 384
fill "$home/Library/Caches/com.ejemplo.foton" 192
for id in com.ejemplo.lienzo com.ejemplo.radio com.ejemplo.mapas com.ejemplo.notas com.ejemplo.foton com.ejemplo.video com.ejemplo.contable com.ejemplo.traductor; do
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$home/Library/Preferences/$id.plist"
done

# Restos de apps que ya no están.
fill "$home/Library/Application Support/com.ejemplo.videopro" 816
fill "$home/Library/Saved Application State/com.ejemplo.videopro.savedState" 16
fill "$home/Library/Application Support/com.ejemplo.carreras" 96
fill "$home/Library/Caches/com.ejemplo.carreras" 32
fill "$home/Library/Application Support/org.ejemplo.traductor" 32
for id in com.ejemplo.videopro com.ejemplo.carreras org.ejemplo.traductor; do
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$home/Library/Preferences/$id.plist"
done
age "$home/Library/Application Support/com.ejemplo.videopro" 120

# Barra del disco: medición guardada con un reparto creíble (el total y el disponible son los del disco real).
mkdir -p "$home/Library/Application Support/Margin"
gb() { echo $(( $1 * 1000 * 1000 * 1000 / 10 )); }
cat > "$home/Library/Application Support/Margin/desglose.json" <<JSON
{"available":0,"date":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","total":0,"segments":[
{"bytes":$(gb 312),"kind":"apps","partial":false},
{"bytes":$(gb 486),"kind":"personal","partial":false},
{"bytes":$(gb 274),"kind":"appData","partial":false},
{"bytes":$(gb 421),"kind":"development","partial":false},
{"bytes":$(gb 598),"kind":"macOS","partial":false},
{"bytes":$(gb 12),"kind":"trash","partial":false},
{"bytes":0,"kind":"purgeable","partial":false},
{"bytes":0,"kind":"system","partial":false}]}
JSON
echo "Carpeta de prueba lista en $home (semillas en $home.semillas)."
