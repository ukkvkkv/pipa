#!/bin/bash
set -euo pipefail

# Сборка «Pipa.app»: один бандл, внутри всё нужное —
# интерфейс на SwiftUI, ipatool-cpp и ideviceinstaller со своими
# библиотеками из Homebrew (у пользователя Homebrew не нужен).

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Pipa.app"
VERSION="1.13.0"
SCRATCH="$(getconf DARWIN_USER_CACHE_DIR)/pipa/swift-build"

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

echo "Собираю интерфейс…"
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --show-bin-path)/Pipa"

# Liquid Glass включается по версии SDK в LC_BUILD_VERSION, а SwiftPM пишет туда minos.
SDK_VER="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-version)"
MIN_OS="$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
vtool -set-build-version macos "$MIN_OS" "$SDK_VER" -replace -output "$BIN" "$BIN"

# --------------------------------------------------------------- бандл
echo "Собираю бандл…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Pipa"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# ipatool под архитектуру сборки (интерфейс и библиотеки Homebrew — тоже только она).
case "$(uname -m)" in arm64) IPA_ARCH=arm64 ;; *) IPA_ARCH=amd64 ;; esac
cp "$ROOT/vendor/ipatool/ipatool-cpp-macOS-$IPA_ARCH" "$APP/Contents/Helpers/ipatool"
chmod +x "$APP/Contents/Helpers/ipatool"

# ideviceinstaller / ideviceinfo + их dylib из Homebrew, пути переписаны на бандл.
FW="$APP/Contents/Frameworks"
bundle_deps() {
  local file="$1" is_lib="$2"
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    [[ "$dep" == /opt/homebrew/* || "$dep" == /usr/local/* ]] || continue
    local name; name="$(basename "$dep")"
    if [[ ! -f "$FW/$name" ]]; then
      cp "$(readlink -f "$dep")" "$FW/$name"
      chmod u+w "$FW/$name"
      install_name_tool -id "@loader_path/$name" "$FW/$name" 2>/dev/null
      bundle_deps "$FW/$name" 1
    fi
    if [[ "$is_lib" == 1 ]]; then
      install_name_tool -change "$dep" "@loader_path/$name" "$file" 2>/dev/null
    else
      install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$file" 2>/dev/null
    fi
  done
}
for tool in ideviceinstaller ideviceinfo; do
  SRC_TOOL="$(command -v $tool || true)"
  if [[ -z "$SRC_TOOL" ]]; then echo "ВНИМАНИЕ: $tool не найден — установка на iPhone будет недоступна"; continue; fi
  cp "$(readlink -f "$SRC_TOOL")" "$APP/Contents/Helpers/$tool"
  chmod u+w "$APP/Contents/Helpers/$tool"
  bundle_deps "$APP/Contents/Helpers/$tool" 0
done

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
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Подпись «на месте»: сначала вложенное, потом бандл.
find "$APP/Contents/Frameworks" "$APP/Contents/Helpers" -type f -exec codesign --force --sign - {} \; 2>/dev/null
codesign --force --sign - "$APP"
xattr -cr "$APP"

echo
echo "Готово: $APP ($(du -sh "$APP" | cut -f1))"
