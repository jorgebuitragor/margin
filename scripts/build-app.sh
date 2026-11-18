#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/gestor-espacio-clang-cache"
swift build -c release --disable-sandbox --scratch-path "${TMPDIR:-/tmp}/gestor-espacio-build"
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox --scratch-path "${TMPDIR:-/tmp}/gestor-espacio-build")"
app_dir="${TMPDIR:-/tmp}/gestor-espacio-local/Gestor Espacio.app"
mkdir -p "$PWD/dist"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/GestorEspacio" "$app_dir/Contents/MacOS/GestorEspacio"
cp "$bin_dir/espacio" "$PWD/dist/espacio"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GestorEspacio</string>
<key>CFBundleIdentifier</key><string>local.gestorespacio.mac</string>
<key>CFBundleName</key><string>Gestor Espacio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --norsrc --keepParent "$app_dir" "$PWD/dist/GestorEspacio.zip"
printf 'App local creada: %s\nZIP: %s\n' "$app_dir" "$PWD/dist/GestorEspacio.zip"
