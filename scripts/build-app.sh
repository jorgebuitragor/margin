#!/bin/bash
# Compila Margin.app (firmada ad hoc) y el binario `margin` de la terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/margin-clang-cache"
scratch="${TMPDIR:-/tmp}/margin-build"
swift build -c release --disable-sandbox --scratch-path "$scratch"
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox --scratch-path "$scratch")"
app_dir="${TMPDIR:-/tmp}/margin-local/Margin.app"
rm -rf "$app_dir"
mkdir -p "$PWD/dist" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MarginApp" "$app_dir/Contents/MacOS/MarginApp"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp "$bin_dir/margin" "$PWD/dist/margin"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MarginApp</string>
<key>CFBundleIdentifier</key><string>local.margin.mac</string>
<key>CFBundleName</key><string>Margin</string>
<key>CFBundleDisplayName</key><string>Margin</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleDevelopmentRegion</key><string>es</string>
<key>CFBundleLocalizations</key><array><string>es</string><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Margin le pide a Finder que vacíe la Papelera cuando tú lo confirmas.</string>
</dict></plist>
PLIST
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --norsrc --keepParent "$app_dir" "$PWD/dist/Margin.zip"
printf 'App local creada: %s\nZIP: %s\n' "$app_dir" "$PWD/dist/Margin.zip"
