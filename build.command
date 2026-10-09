#!/bin/bash
set -euo pipefail

# Сборка «Pipa.app»: один universal-бандл (Apple Silicon + Intel, macOS 14+),
# внутри всё нужное — интерфейс на SwiftUI, ipatool-cpp и ideviceinstaller
# (vendor/idevice, собран статически своим build.sh — Homebrew не нужен).

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Pipa.app"
VERSION="1.14.0"
SCRATCH="$(getconf DARWIN_USER_CACHE_DIR)pipa/swift-build"
MIN_MACOS="14.0"

# --------------------------------------------------------------- иконка
ICON="$ROOT/assets/AppIcon.icns"
if [[ ! -f "$ICON" || "$ROOT/assets/logo.png" -nt "$ICON" ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/assets/logo.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ROOT/assets/logo.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON"
fi

# --------------------------------------------------------------- сборка
# В CLT нет SwiftUIMacros для SDK 27 — собираем против SDK 26 (там @State
# обычная обёртка), если плагина нет.
PLUGINS="$(dirname "$(xcrun --find swift-frontend)")/../lib/swift/host/plugins"
SDK26="$(dirname "$(xcrun --show-sdk-path)")/MacOSX26.sdk"
if [[ ! -f "$PLUGINS/libSwiftUIMacros.dylib" && -d "$SDK26" ]]; then
  export SDKROOT="$(cd "$SDK26" && pwd)"
fi

# Каждая архитектура — своей сборкой, потом lipo. Liquid Glass включается по
# версии SDK в LC_BUILD_VERSION, а SwiftPM пишет туда minos — чиним vtool.
SDK_VER="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-version)"
THIN=()
for arch in arm64 x86_64; do
  echo "Собираю интерфейс ($arch)…"
  args=(--package-path "$ROOT" --scratch-path "$SCRATCH-$arch" -c release --triple "$arch-apple-macosx$MIN_MACOS")
  swift build "${args[@]}"
  bin="$(swift build "${args[@]}" --show-bin-path)/Pipa"
  vtool -set-build-version macos "$MIN_MACOS" "$SDK_VER" -replace -output "$bin.sdk" "$bin"
  THIN+=("$bin.sdk")
done
BIN="$(mktemp -d)/Pipa"
lipo -create "${THIN[@]}" -output "$BIN"

# --------------------------------------------------------------- бандл
echo "Собираю бандл…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN" "$APP/Contents/MacOS/Pipa"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# ipatool: релиз ipatool-cpp — два отдельных файла, склеиваем в один.
lipo -create "$ROOT/vendor/ipatool/ipatool-cpp-macOS-arm64" "$ROOT/vendor/ipatool/ipatool-cpp-macOS-amd64" \
  -output "$APP/Contents/Helpers/ipatool"
cp "$ROOT/vendor/idevice/ideviceinstaller" "$ROOT/vendor/idevice/ideviceinfo" "$APP/Contents/Helpers/"
chmod +x "$APP/Contents/Helpers/"*

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pipa</string>
  <key>CFBundleDisplayName</key><string>Pipa</string>
  <key>CFBundleIdentifier</key><string>io.github.ukkvkkv.pipa</string>
  <key>CFBundleExecutable</key><string>Pipa</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Подпись «на месте»: сначала вложенное, потом бандл.
find "$APP/Contents/Helpers" -type f -exec codesign --force --sign - {} \;
codesign --force --sign - "$APP"
xattr -cr "$APP"

echo
echo "Готово: $APP ($(du -sh "$APP" | cut -f1))"
