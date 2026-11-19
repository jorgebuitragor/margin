#!/bin/bash
# Compila Margin.app y el binario `margin` de la terminal. La app se firma con la identidad «Margin Local»
# (scripts/firma-local.sh) para que macOS conserve sus permisos entre versiones; si no existe, se firma ad hoc.
#
# La versión sale de VERSION y el número de compilación, del número de commits (siempre crece, como pide Sparkle).
# La CLI va dentro de la app (Contents/Helpers/margin): así cada actualización de la app también la actualiza.
# Las actualizaciones automáticas se activan solo si existe Resources/sparkle-clave-publica.txt (la crea
# scripts/release.sh la primera vez).
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/margin-clang-cache"
scratch="${TMPDIR:-/tmp}/margin-build"
swift build -c release --disable-sandbox --scratch-path "$scratch"
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox --scratch-path "$scratch")"
version="$(tr -d '[:space:]' < VERSION)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
app_dir="${TMPDIR:-/tmp}/margin-local/Margin.app"
rm -rf "$app_dir"
mkdir -p "$PWD/dist" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Helpers" "$app_dir/Contents/Frameworks"
cp "$bin_dir/MarginApp" "$app_dir/Contents/MacOS/MarginApp"
cp "$bin_dir/margin" "$app_dir/Contents/Helpers/margin"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
# Sparkle: el framework va en Contents/Frameworks y el ejecutable lo busca ahí.
ditto "$bin_dir/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_dir/Contents/MacOS/MarginApp" 2>/dev/null || true
updates=""
if [ -s Resources/sparkle-clave-publica.txt ]; then
  updates="<key>SUFeedURL</key><string>https://github.com/jorgebuitragor/margin/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < Resources/sparkle-clave-publica.txt)</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUEnableSystemProfiling</key><false/>"
fi
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MarginApp</string>
<key>CFBundleIdentifier</key><string>local.margin.mac</string>
<key>CFBundleName</key><string>Margin</string>
<key>CFBundleDisplayName</key><string>Margin</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
<key>CFBundleDevelopmentRegion</key><string>es</string>
<key>CFBundleLocalizations</key><array><string>es</string><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Margin le pide a Finder que vacíe la Papelera cuando tú lo confirmas.</string>
$updates
</dict></plist>
PLIST
xattr -cr "$app_dir"
if security find-certificate -c "Margin Local" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  identity="Margin Local"
else
  echo "Aviso: no existe la identidad «Margin Local» (bash scripts/firma-local.sh); se firma ad hoc y macOS puede olvidar los permisos." >&2
  identity="-"
fi
# De dentro hacia fuera: la CLI y luego la app. Sparkle conserva la firma de sus autores.
codesign --force --sign "$identity" "$app_dir/Contents/Helpers/margin"
codesign --force --sign "$identity" "$app_dir"
cp "$app_dir/Contents/Helpers/margin" "$PWD/dist/margin"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --norsrc --keepParent "$app_dir" "$PWD/dist/Margin.zip"
printf 'App local creada: %s (versión %s, compilación %s)\nZIP: %s\n' "$app_dir" "$version" "$build" "$PWD/dist/Margin.zip"
